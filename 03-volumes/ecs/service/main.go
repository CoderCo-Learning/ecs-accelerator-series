package main

import (
	"embed"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"
)

//go:embed static/*
var staticFiles embed.FS

const (
	volumePath    = "/mnt/efs"
	maxUploadSize = 10 << 20
	uploadsDir    = "/mnt/efs/uploads"
)

func init() {
	// Create uploads directory on startup
	if err := os.MkdirAll(uploadsDir, 0755); err != nil {
		log.Printf("Failed to create uploads directory: %v", err)
	} else {
		log.Println("Uploads directory ready")
	}
}

func main() {
	// Serve embedded static files
	http.Handle("/static/", http.FileServer(http.FS(staticFiles)))

	http.HandleFunc("/", serveIndex)
	http.HandleFunc("/health", healthHandler)
	http.HandleFunc("/api/info", apiInfoHandler)
	http.HandleFunc("/api/files", filesHandler)
	http.HandleFunc("/api/upload", uploadHandler)
	http.HandleFunc("/api/delete", deleteHandler)

	log.Println("starting server on :8080")
	http.ListenAndServe(":8080", nil)
}

func serveIndex(w http.ResponseWriter, r *http.Request) {
	data, _ := staticFiles.ReadFile("static/index.html")
	w.Header().Set("Content-Type", "text/html")
	w.Write(data)
}

func healthHandler(w http.ResponseWriter, r *http.Request) {
	fmt.Fprintln(w, "ok")
}

func checkEFSMounted() string {
	if stat, err := os.Stat(uploadsDir); err == nil && stat.IsDir() {
		return "MOUNTED ✓"
	}
	return "NOT MOUNTED"
}

func apiInfoHandler(w http.ResponseWriter, r *http.Request) {
	hostname, _ := os.Hostname()

	// More robust EFS mount check
	mounted := checkEFSMounted()

	w.Header().Set("Content-Type", "application/json")
	fmt.Fprintf(w, `{"taskId":"%s","efsMount":"%s","efsStatus":"%s"}`,
		hostname, volumePath, mounted)
}

func filesHandler(w http.ResponseWriter, r *http.Request) {
	entries, err := os.ReadDir(uploadsDir)
	if err != nil {
		// Directory doesn't exist - return empty array instead of crashing
		hostname, _ := os.Hostname()
		w.Header().Set("Content-Type", "application/json")
		fmt.Fprintf(w, `{"taskId":"%s","files":[]}`, hostname)
		return
	}

	hostname, _ := os.Hostname()

	w.Header().Set("Content-Type", "application/json")
	w.Write([]byte(`{"taskId":"` + hostname + `","files":[`))

	first := true
	for _, entry := range entries {
		// Skip hidden files
		if strings.HasPrefix(entry.Name(), ".") {
			continue
		}

		info, _ := entry.Info()
		if !first {
			w.Write([]byte(","))
		}
		first = false
		fmt.Fprintf(w, `{"name":"%s","size":%d,"modified":"%s"}`,
			entry.Name(), info.Size(), info.ModTime().Format(time.RFC3339))
	}

	w.Write([]byte(`]}`))
}

func uploadHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	r.Body = http.MaxBytesReader(w, r.Body, maxUploadSize)
	if err := r.ParseMultipartForm(maxUploadSize); err != nil {
		http.Error(w, fmt.Sprintf(`{"error":"file too large"}`, err), http.StatusBadRequest)
		return
	}

	file, header, err := r.FormFile("file")
	if err != nil {
		http.Error(w, fmt.Sprintf(`{"error":"%v"}`, err), http.StatusBadRequest)
		return
	}
	defer file.Close()

	// Sanitise filename
	filename := filepath.Base(header.Filename)
	filename = strings.ReplaceAll(filename, " ", "_")

	// Add timestamp to avoid collisions
	ext := filepath.Ext(filename)
	nameWithoutExt := strings.TrimSuffix(filename, ext)
	finalName := fmt.Sprintf("%s_%d%s", nameWithoutExt, time.Now().Unix(), ext)

	dst, err := os.Create(filepath.Join(uploadsDir, finalName))
	if err != nil {
		http.Error(w, fmt.Sprintf(`{"error":"%v"}`, err), http.StatusInternalServerError)
		return
	}
	defer dst.Close()

	if _, err := io.Copy(dst, file); err != nil {
		http.Error(w, fmt.Sprintf(`{"error":"%v"}`, err), http.StatusInternalServerError)
		return
	}

	hostname, _ := os.Hostname()
	w.Header().Set("Content-Type", "application/json")
	fmt.Fprintf(w, `{"success":true,"filename":"%s","taskId":"%s"}`, finalName, hostname)
}

func deleteHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodDelete {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	filename := r.URL.Query().Get("file")
	if filename == "" {
		http.Error(w, `{"error":"missing file parameter"}`, http.StatusBadRequest)
		return
	}

	filepath := filepath.Join(uploadsDir, filepath.Base(filename))
	if err := os.Remove(filepath); err != nil {
		http.Error(w, fmt.Sprintf(`{"error":"%v"}`, err), http.StatusInternalServerError)
		return
	}

	hostname, _ := os.Hostname()
	w.Header().Set("Content-Type", "application/json")
	fmt.Fprintf(w, `{"success":true,"taskId":"%s"}`, hostname)
}
