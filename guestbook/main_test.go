package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestVisit(t *testing.T) {
	h := (&server{instance: "test", host: "box"}).routes()

	body := `{"name":"GitHub Actions","run":"42","message":"hello","results":[{"target":"k3s API","want":"block","got":"hidden"}]}`
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodPost, "/visit", strings.NewReader(body)))
	if rec.Code != http.StatusOK || !strings.Contains(rec.Body.String(), "GitHub Actions run #42") {
		t.Fatalf("POST /visit = %d %q", rec.Code, rec.Body)
	}

	rec = httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/visits", nil))
	var got struct{ Visits []Visit }
	if err := json.NewDecoder(rec.Body).Decode(&got); err != nil {
		t.Fatal(err)
	}
	if len(got.Visits) != 1 || got.Visits[0].Message != "hello" || got.Visits[0].Results[0].Got != "hidden" {
		t.Fatalf("GET /visits = %+v", got.Visits)
	}

	rec = httptest.NewRecorder()
	big := `{"message":"` + strings.Repeat("x", 1<<17) + `"}`
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodPost, "/visit", strings.NewReader(big)))
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("oversized POST /visit = %d, want 400", rec.Code)
	}

	rec = httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/", nil))
	if rec.Code != http.StatusOK || !strings.Contains(rec.Body.String(), "<title>") {
		t.Fatalf("GET / = %d", rec.Code)
	}
}

func TestVisitsCapped(t *testing.T) {
	s := &server{}
	h := s.routes()
	for range maxVisits + 5 {
		h.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest(http.MethodPost, "/visit", strings.NewReader(`{}`)))
	}
	if len(s.visits) != maxVisits {
		t.Fatalf("kept %d visits, want %d", len(s.visits), maxVisits)
	}
}
