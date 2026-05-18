// Package metrics exposes a minimal Prometheus-compatible /metrics
// endpoint. The implementation is hand-rolled (no prometheus/client_go
// dependency) — exposition format is simple enough to emit directly and
// keeps go.mod thin during the night-sprint phase. A follow-up can swap
// to client_go once we need histograms with sliding windows.
//
// Counters track http_requests_total {method,status_class}. The
// http_request_duration_seconds summary is approximated by sampling p50
// and p95 from a ring buffer (last 1024 requests) — fine for dashboard
// alerting at our request volume (~50 req/sec target).
//
// DB pool stats sample sql.DBStats every scrape — open/idle/wait counts
// and wait_count_total / wait_duration_total surface saturation early.
package metrics

import (
	"database/sql"
	"fmt"
	"net/http"
	"runtime"
	"sort"
	"strconv"
	"sync"
	"sync/atomic"
	"time"
)

// counters keyed by "method|status_class". status_class is "2xx", "3xx", etc.
type counterMap struct {
	mu     sync.RWMutex
	values map[string]*uint64
}

func newCounterMap() *counterMap {
	return &counterMap{values: make(map[string]*uint64, 32)}
}

func (c *counterMap) inc(key string) {
	c.mu.RLock()
	v, ok := c.values[key]
	c.mu.RUnlock()
	if ok {
		atomic.AddUint64(v, 1)
		return
	}
	c.mu.Lock()
	if v, ok := c.values[key]; ok {
		atomic.AddUint64(v, 1)
	} else {
		var n uint64 = 1
		c.values[key] = &n
	}
	c.mu.Unlock()
}

func (c *counterMap) snapshot() map[string]uint64 {
	c.mu.RLock()
	defer c.mu.RUnlock()
	out := make(map[string]uint64, len(c.values))
	for k, v := range c.values {
		out[k] = atomic.LoadUint64(v)
	}
	return out
}

// latencyRing is a fixed-size ring buffer of request durations in
// microseconds. Lock-free for writes (atomic index advance), best-effort
// quantile computation on scrape.
type latencyRing struct {
	mu    sync.Mutex
	buf   []uint64
	idx   uint64
	count uint64
}

func newLatencyRing(size int) *latencyRing {
	return &latencyRing{buf: make([]uint64, size)}
}

func (lr *latencyRing) observe(micros uint64) {
	lr.mu.Lock()
	i := lr.idx % uint64(len(lr.buf))
	lr.buf[i] = micros
	lr.idx++
	if lr.count < uint64(len(lr.buf)) {
		lr.count++
	}
	lr.mu.Unlock()
}

// quantiles returns p50, p95, p99. Returns zeros if no samples.
func (lr *latencyRing) quantiles() (p50, p95, p99 uint64) {
	lr.mu.Lock()
	if lr.count == 0 {
		lr.mu.Unlock()
		return 0, 0, 0
	}
	sample := make([]uint64, lr.count)
	copy(sample, lr.buf[:lr.count])
	lr.mu.Unlock()

	sort.Slice(sample, func(i, j int) bool { return sample[i] < sample[j] })
	pick := func(p float64) uint64 {
		if len(sample) == 0 {
			return 0
		}
		idx := int(float64(len(sample)) * p)
		if idx >= len(sample) {
			idx = len(sample) - 1
		}
		return sample[idx]
	}
	return pick(0.50), pick(0.95), pick(0.99)
}

// global state — single registry per process.
var (
	reqCount = newCounterMap()
	latency  = newLatencyRing(1024)
	startup  = time.Now()
)

// RecordRequest is called by the Logger middleware on every response.
func RecordRequest(method string, status int, duration time.Duration) {
	cls := statusClass(status)
	reqCount.inc(method + "|" + cls)
	latency.observe(uint64(duration.Microseconds()))
}

func statusClass(status int) string {
	switch {
	case status >= 200 && status < 300:
		return "2xx"
	case status >= 300 && status < 400:
		return "3xx"
	case status >= 400 && status < 500:
		return "4xx"
	case status >= 500:
		return "5xx"
	default:
		return "other"
	}
}

// Register wires GET /metrics on the mux. db may be nil — that suppresses
// the DB-pool gauges so this package stays useful in tests too.
func Register(mux *http.ServeMux, db *sql.DB) {
	mux.HandleFunc("GET /metrics", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/plain; version=0.0.4; charset=utf-8")
		write := func(format string, args ...any) {
			fmt.Fprintf(w, format, args...)
		}

		// http_requests_total
		write("# HELP gastrocore_http_requests_total Total HTTP requests.\n")
		write("# TYPE gastrocore_http_requests_total counter\n")
		snap := reqCount.snapshot()
		for key, v := range snap {
			method, cls := splitKey(key)
			write("gastrocore_http_requests_total{method=%q,status_class=%q} %d\n", method, cls, v)
		}

		// http_request_duration_seconds (summary-ish)
		p50, p95, p99 := latency.quantiles()
		write("# HELP gastrocore_http_request_duration_seconds Approximate request latency.\n")
		write("# TYPE gastrocore_http_request_duration_seconds summary\n")
		write("gastrocore_http_request_duration_seconds{quantile=\"0.5\"} %s\n", microsToSeconds(p50))
		write("gastrocore_http_request_duration_seconds{quantile=\"0.95\"} %s\n", microsToSeconds(p95))
		write("gastrocore_http_request_duration_seconds{quantile=\"0.99\"} %s\n", microsToSeconds(p99))

		// process_uptime_seconds
		write("# HELP gastrocore_process_uptime_seconds Seconds since process start.\n")
		write("# TYPE gastrocore_process_uptime_seconds gauge\n")
		write("gastrocore_process_uptime_seconds %d\n", int64(time.Since(startup).Seconds()))

		// goroutines
		write("# HELP go_goroutines Number of goroutines.\n")
		write("# TYPE go_goroutines gauge\n")
		write("go_goroutines %d\n", runtime.NumGoroutine())

		// memory
		var mem runtime.MemStats
		runtime.ReadMemStats(&mem)
		write("# HELP go_memstats_alloc_bytes Heap memory currently allocated.\n")
		write("# TYPE go_memstats_alloc_bytes gauge\n")
		write("go_memstats_alloc_bytes %d\n", mem.Alloc)

		// DB pool
		if db != nil {
			stats := db.Stats()
			write("# HELP gastrocore_db_pool_open Open DB connections.\n")
			write("# TYPE gastrocore_db_pool_open gauge\n")
			write("gastrocore_db_pool_open %d\n", stats.OpenConnections)
			write("# HELP gastrocore_db_pool_in_use DB connections in use.\n")
			write("# TYPE gastrocore_db_pool_in_use gauge\n")
			write("gastrocore_db_pool_in_use %d\n", stats.InUse)
			write("# HELP gastrocore_db_pool_idle DB connections idle.\n")
			write("# TYPE gastrocore_db_pool_idle gauge\n")
			write("gastrocore_db_pool_idle %d\n", stats.Idle)
			write("# HELP gastrocore_db_pool_wait_count_total DB connection wait events.\n")
			write("# TYPE gastrocore_db_pool_wait_count_total counter\n")
			write("gastrocore_db_pool_wait_count_total %d\n", stats.WaitCount)
			write("# HELP gastrocore_db_pool_wait_duration_seconds_total Total time spent waiting for a DB connection.\n")
			write("# TYPE gastrocore_db_pool_wait_duration_seconds_total counter\n")
			write("gastrocore_db_pool_wait_duration_seconds_total %s\n", microsToSeconds(uint64(stats.WaitDuration.Microseconds())))
		}
	})
}

func splitKey(key string) (method, cls string) {
	for i := 0; i < len(key); i++ {
		if key[i] == '|' {
			return key[:i], key[i+1:]
		}
	}
	return key, ""
}

func microsToSeconds(us uint64) string {
	// Format with 6 fractional digits — keeps Prometheus parser happy and
	// stays readable in dashboards.
	return strconv.FormatFloat(float64(us)/1_000_000.0, 'f', 6, 64)
}
