// Package email is a thin SMTP wrapper for the reporting automation feature.
// It uses Go's stdlib net/smtp so there's no third-party dep to manage.
//
// If config.SMTPHost is unset, Send returns nil after logging the rendered
// body — keeps dev environments noise-free without skipping the audit row.
package email

import (
	"crypto/tls"
	"errors"
	"fmt"
	"log/slog"
	"net"
	"net/smtp"
	"strings"
	"time"

	"github.com/gastrocore/server/internal/shared/config"
)

type Sender struct {
	cfg *config.Config
}

func NewSender(cfg *config.Config) *Sender { return &Sender{cfg: cfg} }

// Configured reports whether SMTP credentials are present. Callers may want
// to short-circuit work that would have nowhere to deliver.
func (s *Sender) Configured() bool { return s.cfg != nil && s.cfg.SMTPHost != "" }

// Message is the minimal envelope we need for HTML+text reports.
type Message struct {
	To       []string
	Subject  string
	HTMLBody string
	TextBody string // optional plain-text alternative; if empty, derived from HTML
	ReplyTo  string
}

// Send dispatches the message. Returns nil on dry-run (no SMTPHost).
func (s *Sender) Send(m Message) error {
	if len(m.To) == 0 {
		return errors.New("email: no recipients")
	}
	if m.Subject == "" {
		return errors.New("email: subject required")
	}
	if m.HTMLBody == "" && m.TextBody == "" {
		return errors.New("email: empty body")
	}
	if !s.Configured() {
		slog.Info("email: dry-run (SMTP_HOST empty)",
			"to", m.To,
			"subject", m.Subject,
			"bytes", len(m.HTMLBody)+len(m.TextBody),
		)
		return nil
	}

	raw, err := buildMIME(s.cfg.SMTPFrom, m)
	if err != nil {
		return fmt.Errorf("email: build mime: %w", err)
	}

	addr := fmt.Sprintf("%s:%d", s.cfg.SMTPHost, s.cfg.SMTPPort)
	auth := smtp.PlainAuth("", s.cfg.SMTPUser, s.cfg.SMTPPassword, s.cfg.SMTPHost)

	from := parseAddress(s.cfg.SMTPFrom)
	if from == "" {
		from = s.cfg.SMTPUser
	}

	// Port 465 = implicit TLS; port 587 = STARTTLS upgrade after EHLO.
	// Default smtp.SendMail does STARTTLS on the server's hint, which fits
	// both 587 and most modern 25 relays. For 465 we dial TLS ourselves.
	if s.cfg.SMTPPort == 465 {
		return sendImplicitTLS(addr, s.cfg.SMTPHost, auth, from, m.To, raw)
	}
	return smtp.SendMail(addr, auth, from, m.To, raw)
}

func sendImplicitTLS(addr, host string, auth smtp.Auth, from string, to []string, msg []byte) error {
	dialer := &net.Dialer{Timeout: 15 * time.Second}
	tlsConn, err := tls.DialWithDialer(dialer, "tcp", addr, &tls.Config{ServerName: host})
	if err != nil {
		return err
	}
	c, err := smtp.NewClient(tlsConn, host)
	if err != nil {
		return err
	}
	defer c.Close()
	if err := c.Auth(auth); err != nil {
		return err
	}
	if err := c.Mail(from); err != nil {
		return err
	}
	for _, addr := range to {
		if err := c.Rcpt(addr); err != nil {
			return err
		}
	}
	w, err := c.Data()
	if err != nil {
		return err
	}
	if _, err := w.Write(msg); err != nil {
		return err
	}
	if err := w.Close(); err != nil {
		return err
	}
	return c.Quit()
}

func buildMIME(from string, m Message) ([]byte, error) {
	var buf strings.Builder
	boundary := "gc-mime-" + fmt.Sprintf("%d", time.Now().UnixNano())

	buf.WriteString("From: " + from + "\r\n")
	buf.WriteString("To: " + strings.Join(m.To, ", ") + "\r\n")
	if m.ReplyTo != "" {
		buf.WriteString("Reply-To: " + m.ReplyTo + "\r\n")
	}
	buf.WriteString("Subject: " + encodeSubject(m.Subject) + "\r\n")
	buf.WriteString("MIME-Version: 1.0\r\n")
	buf.WriteString("Content-Type: multipart/alternative; boundary=\"" + boundary + "\"\r\n")
	buf.WriteString("\r\n")

	text := m.TextBody
	if text == "" {
		text = htmlToPlain(m.HTMLBody)
	}
	buf.WriteString("--" + boundary + "\r\n")
	buf.WriteString("Content-Type: text/plain; charset=\"UTF-8\"\r\n")
	buf.WriteString("Content-Transfer-Encoding: 8bit\r\n\r\n")
	buf.WriteString(text)
	buf.WriteString("\r\n")

	if m.HTMLBody != "" {
		buf.WriteString("--" + boundary + "\r\n")
		buf.WriteString("Content-Type: text/html; charset=\"UTF-8\"\r\n")
		buf.WriteString("Content-Transfer-Encoding: 8bit\r\n\r\n")
		buf.WriteString(m.HTMLBody)
		buf.WriteString("\r\n")
	}

	buf.WriteString("--" + boundary + "--\r\n")
	return []byte(buf.String()), nil
}

// encodeSubject wraps non-ASCII subjects in MIME B-encoding so Turkish, German
// umlauts, French accents survive MTAs that mangle 8-bit headers.
func encodeSubject(s string) string {
	for _, r := range s {
		if r > 127 {
			// RFC 2047 base64 encoding
			return "=?UTF-8?B?" + base64Encode(s) + "?="
		}
	}
	return s
}

func base64Encode(s string) string {
	const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
	b := []byte(s)
	var out strings.Builder
	for i := 0; i < len(b); i += 3 {
		var v uint32
		switch {
		case i+3 <= len(b):
			v = uint32(b[i])<<16 | uint32(b[i+1])<<8 | uint32(b[i+2])
			out.WriteByte(alphabet[(v>>18)&0x3F])
			out.WriteByte(alphabet[(v>>12)&0x3F])
			out.WriteByte(alphabet[(v>>6)&0x3F])
			out.WriteByte(alphabet[v&0x3F])
		case i+2 == len(b):
			v = uint32(b[i])<<16 | uint32(b[i+1])<<8
			out.WriteByte(alphabet[(v>>18)&0x3F])
			out.WriteByte(alphabet[(v>>12)&0x3F])
			out.WriteByte(alphabet[(v>>6)&0x3F])
			out.WriteByte('=')
		case i+1 == len(b):
			v = uint32(b[i]) << 16
			out.WriteByte(alphabet[(v>>18)&0x3F])
			out.WriteByte(alphabet[(v>>12)&0x3F])
			out.WriteString("==")
		}
	}
	return out.String()
}

// htmlToPlain is a very small HTML→text fallback so the multipart/alternative
// always has a text/plain part. Not a real renderer.
func htmlToPlain(html string) string {
	s := html
	repl := []struct{ from, to string }{
		{"<br>", "\n"}, {"<br/>", "\n"}, {"<br />", "\n"},
		{"</p>", "\n\n"}, {"</tr>", "\n"}, {"</h1>", "\n\n"}, {"</h2>", "\n\n"},
		{"</li>", "\n"}, {"&nbsp;", " "}, {"&amp;", "&"}, {"&lt;", "<"}, {"&gt;", ">"},
	}
	for _, r := range repl {
		s = strings.ReplaceAll(s, r.from, r.to)
	}
	out := strings.Builder{}
	inTag := false
	for _, c := range s {
		switch {
		case c == '<':
			inTag = true
		case c == '>':
			inTag = false
		case !inTag:
			out.WriteRune(c)
		}
	}
	return strings.TrimSpace(out.String())
}

// parseAddress extracts the bare email from "Name <foo@bar.com>" or returns
// the input if there are no angle brackets.
func parseAddress(s string) string {
	if i := strings.IndexByte(s, '<'); i >= 0 {
		if j := strings.IndexByte(s[i+1:], '>'); j >= 0 {
			return s[i+1 : i+1+j]
		}
	}
	return strings.TrimSpace(s)
}
