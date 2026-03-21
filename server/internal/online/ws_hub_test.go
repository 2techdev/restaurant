package online

import (
	"encoding/json"
	"testing"
	"time"
)

// TestOnlineHub_BroadcastDeliversSameRestaurant verifies that a message is
// delivered to a client registered for the matching restaurant_id.
func TestOnlineHub_BroadcastDeliversSameRestaurant(t *testing.T) {
	hub := NewOnlineHub()
	go hub.Run()

	recv := make(chan []byte, 4)
	c := &onlineWSClient{restaurantID: "r1", send: recv}
	hub.register(c)

	hub.Broadcast(OnlineWSMessage{
		Type:         "new_order",
		RestaurantID: "r1",
		OrderID:      "ord-1",
		Data:         map[string]any{"order_number": 7},
	})

	select {
	case msg := <-recv:
		var m OnlineWSMessage
		if err := json.Unmarshal(msg, &m); err != nil {
			t.Fatal(err)
		}
		if m.Type != "new_order" {
			t.Errorf("expected type=new_order, got %s", m.Type)
		}
		if m.OrderID != "ord-1" {
			t.Errorf("expected order_id=ord-1, got %s", m.OrderID)
		}
	case <-time.After(500 * time.Millisecond):
		t.Error("client should have received the broadcast within 500ms")
	}
}

// TestOnlineHub_BroadcastIsolatesRestaurants verifies that a message for
// restaurant "r1" is NOT delivered to a client subscribed to "r2".
func TestOnlineHub_BroadcastIsolatesRestaurants(t *testing.T) {
	hub := NewOnlineHub()
	go hub.Run()

	recv1 := make(chan []byte, 4)
	recv2 := make(chan []byte, 4)
	hub.register(&onlineWSClient{restaurantID: "r1", send: recv1})
	hub.register(&onlineWSClient{restaurantID: "r2", send: recv2})

	hub.Broadcast(OnlineWSMessage{Type: "new_order", RestaurantID: "r1", OrderID: "o1"})

	select {
	case <-recv1:
		// expected
	case <-time.After(500 * time.Millisecond):
		t.Error("r1 client should have received the message")
	}

	select {
	case <-recv2:
		t.Error("r2 client must NOT receive a message meant for r1")
	default:
		// expected
	}
}

// TestOnlineHub_CustomerClientFiltersOtherOrders verifies that a customer
// client (with order_id set) only receives messages for its own order.
func TestOnlineHub_CustomerClientFiltersOtherOrders(t *testing.T) {
	hub := NewOnlineHub()
	go hub.Run()

	myOrder := make(chan []byte, 4)
	otherOrder := make(chan []byte, 4)
	hub.register(&onlineWSClient{restaurantID: "r1", orderID: "my-order", send: myOrder})
	hub.register(&onlineWSClient{restaurantID: "r1", orderID: "other-order", send: otherOrder})

	hub.Broadcast(OnlineWSMessage{
		Type:         "order_status",
		RestaurantID: "r1",
		OrderID:      "my-order",
		Data:         map[string]any{"status": "preparing"},
	})

	select {
	case <-myOrder:
		// expected
	case <-time.After(500 * time.Millisecond):
		t.Error("my-order client should have received the status update")
	}

	select {
	case <-otherOrder:
		t.Error("other-order client must NOT receive a message for a different order")
	default:
		// expected
	}
}

// TestOnlineHub_StaffClientReceivesAllOrders verifies that a staff client
// (empty order_id) receives all order events for its restaurant.
func TestOnlineHub_StaffClientReceivesAllOrders(t *testing.T) {
	hub := NewOnlineHub()
	go hub.Run()

	staffRecv := make(chan []byte, 8)
	hub.register(&onlineWSClient{restaurantID: "r1", orderID: "", send: staffRecv})

	for _, ordID := range []string{"ord-a", "ord-b", "ord-c"} {
		hub.Broadcast(OnlineWSMessage{
			Type: "new_order", RestaurantID: "r1", OrderID: ordID,
		})
	}

	received := 0
	deadline := time.After(500 * time.Millisecond)
	for received < 3 {
		select {
		case <-staffRecv:
			received++
		case <-deadline:
			t.Errorf("staff client should have received 3 messages, got %d", received)
			return
		}
	}
}

// TestOnlineHub_UnregisterStopsDelivery verifies that a client stops receiving
// messages after it is unregistered.
func TestOnlineHub_UnregisterStopsDelivery(t *testing.T) {
	hub := NewOnlineHub()
	go hub.Run()

	recv := make(chan []byte, 4)
	c := &onlineWSClient{restaurantID: "r1", send: recv}
	hub.register(c)
	hub.unregister(c)

	// Channel should be closed; sending via Broadcast must not panic.
	hub.Broadcast(OnlineWSMessage{Type: "new_order", RestaurantID: "r1", OrderID: "x"})

	// Give the goroutine time to process.
	time.Sleep(50 * time.Millisecond)

	select {
	case _, ok := <-recv:
		if ok {
			t.Error("should not receive a message after unregister")
		}
		// closed channel — expected
	default:
		// no message — also fine
	}
}
