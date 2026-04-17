package printers

import "testing"

func TestValidatePrinters_valid(t *testing.T) {
	in := []PrinterConfig{
		{Target: "kitchen", Type: "ethernet", IP: "10.0.0.1", Port: 9100},
		{Target: "kitchen", Type: "ethernet", IP: "10.0.0.2", Port: 9100, IsBackup: true},
		{Target: "bar", Type: "ethernet", IP: "10.0.0.3", Port: 9100},
		{Target: "receipt", Type: "ethernet", IP: "10.0.0.4", Port: 9100},
	}
	if err := validatePrinters(in); err != nil {
		t.Fatalf("expected nil, got %v", err)
	}
}

func TestValidatePrinters_rejectsDuplicatePrimary(t *testing.T) {
	in := []PrinterConfig{
		{Target: "kitchen", Type: "ethernet", IP: "10.0.0.1", Port: 9100},
		{Target: "kitchen", Type: "ethernet", IP: "10.0.0.2", Port: 9100},
	}
	if err := validatePrinters(in); err == nil {
		t.Fatal("expected error for duplicate primary on same target")
	}
}

func TestValidatePrinters_rejectsBadIP(t *testing.T) {
	in := []PrinterConfig{
		{Target: "kitchen", Type: "ethernet", IP: "not-an-ip", Port: 9100},
	}
	if err := validatePrinters(in); err == nil {
		t.Fatal("expected error for invalid IP")
	}
}

func TestValidatePrinters_rejectsBadTarget(t *testing.T) {
	in := []PrinterConfig{
		{Target: "label-printer", Type: "ethernet", IP: "10.0.0.1", Port: 9100},
	}
	if err := validatePrinters(in); err == nil {
		t.Fatal("expected error for invalid target")
	}
}

func TestValidatePrinters_portRange(t *testing.T) {
	in := []PrinterConfig{
		{Target: "kitchen", Type: "ethernet", IP: "10.0.0.1", Port: 0},
	}
	if err := validatePrinters(in); err == nil {
		t.Fatal("expected error for port 0")
	}
}

func TestValidatePrinters_usbSkipsIPCheck(t *testing.T) {
	in := []PrinterConfig{
		{Target: "kitchen", Type: "usb", USBPath: "/dev/usblp0"},
	}
	if err := validatePrinters(in); err != nil {
		t.Fatalf("USB should skip IP validation, got %v", err)
	}
}
