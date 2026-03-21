package kds

import (
	"encoding/json"
	"testing"
	"time"
)

func TestHub_NotifyDeliversTenant(t *testing.T) {
	hub := NewHub()
	go hub.Run()

	recv := make(chan []byte, 4)
	other := make(chan []byte, 4)

	c1 := &kdsClient{deviceID: "kds-1", tenantID: "t1", send: recv}
	c2 := &kdsClient{deviceID: "kds-2", tenantID: "t2", send: other}
	hub.register(c1)
	hub.register(c2)

	hub.Notify(KDSNotification{Type: "new_ticket", TenantID: "t1"})

	select {
	case msg := <-recv:
		var n KDSNotification
		if err := json.Unmarshal(msg, &n); err != nil {
			t.Fatal(err)
		}
		if n.Type != "new_ticket" {
			t.Errorf("expected type=new_ticket, got %s", n.Type)
		}
	case <-time.After(500 * time.Millisecond):
		t.Error("tenant t1 client should have received the notification within 500ms")
	}

	// t2 client must NOT have received the message.
	select {
	case <-other:
		t.Error("cross-tenant notification should not be delivered")
	default:
	}
}

func TestHub_NotifyNewOrder(t *testing.T) {
	hub := NewHub()
	go hub.Run()

	recv := make(chan []byte, 4)
	c := &kdsClient{deviceID: "kds-1", tenantID: "tenant-42", send: recv}
	hub.register(c)

	hub.NotifyNewOrder("tenant-42", "ticket-abc", 5)

	select {
	case msg := <-recv:
		var n KDSNotification
		if err := json.Unmarshal(msg, &n); err != nil {
			t.Fatal(err)
		}
		if n.Type != "new_ticket" {
			t.Errorf("expected new_ticket, got %s", n.Type)
		}
		if n.Ticket == nil || n.Ticket.OrderNumber != 5 {
			t.Errorf("expected order_number=5, got %v", n.Ticket)
		}
	case <-time.After(500 * time.Millisecond):
		t.Error("client should have received new_ticket notification within 500ms")
	}
}

func TestHub_RegisterReplaces(t *testing.T) {
	hub := NewHub()
	go hub.Run()

	old := &kdsClient{deviceID: "dev", tenantID: "t", send: make(chan []byte, 1)}
	hub.register(old)

	fresh := &kdsClient{deviceID: "dev", tenantID: "t", send: make(chan []byte, 1)}
	hub.register(fresh)

	hub.mu.RLock()
	current := hub.clients["dev"]
	hub.mu.RUnlock()

	if current != fresh {
		t.Error("expected fresh client to replace the old one")
	}
}
