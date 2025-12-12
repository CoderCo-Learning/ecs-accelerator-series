package main

import (
	"fmt"
	"log"
	"net/http"
	"os"
	"time"
)

const volumePath = "/mnt/efs"

func main() {
	http.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintln(w, "ok")
	})

	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintln(w, "Hello from ECS Fargate via Serverless Containers!")
	})

	// Write to EFS
	http.HandleFunc("/write", func(w http.ResponseWriter, r *http.Request) {
		message := r.URL.Query().Get("msg")
		if message == "" {
			message = "default message"
		}

		filename := fmt.Sprintf("%s/message-%d.txt", volumePath, time.Now().Unix())
		err := os.WriteFile(filename, []byte(message), 0644)
		if err != nil {
			http.Error(w, fmt.Sprintf("failed to write: %v", err), http.StatusInternalServerError)
			return
		}

		hostname, _ := os.Hostname()
		fmt.Fprintf(w, "wrote to %s from task %s\n", filename, hostname)
	})

	// Read from EFS
	http.HandleFunc("/read", func(w http.ResponseWriter, r *http.Request) {
		entries, err := os.ReadDir(volumePath)
		if err != nil {
			http.Error(w, fmt.Sprintf("failed to read dir: %v", err), http.StatusInternalServerError)
			return
		}

		hostname, _ := os.Hostname()
		fmt.Fprintf(w, "Files in EFS (reading from task %s):\n", hostname)

		if len(entries) == 0 {
			fmt.Fprintln(w, "  (no files yet)")
			return
		}

		for _, entry := range entries {
			filepath := fmt.Sprintf("%s/%s", volumePath, entry.Name())
			content, err := os.ReadFile(filepath)
			if err != nil {
				fmt.Fprintf(w, "  %s (error reading)\n", entry.Name())
				continue
			}
			fmt.Fprintf(w, "  %s: %s\n", entry.Name(), string(content))
		}
	})

	// List task info
	http.HandleFunc("/info", func(w http.ResponseWriter, r *http.Request) {
		hostname, _ := os.Hostname()
		fmt.Fprintf(w, "Task ID: %s\n", hostname)
		fmt.Fprintf(w, "EFS mount: %s\n", volumePath)

		// Check if EFS is mounted
		stat, err := os.Stat(volumePath)
		if err != nil {
			fmt.Fprintf(w, "EFS status: NOT MOUNTED (%v)\n", err)
		} else if stat.IsDir() {
			fmt.Fprintln(w, "EFS status: MOUNTED ✓")
		}
	})

	http.HandleFunc("/delete", func(w http.ResponseWriter, r *http.Request) {
		filename := r.URL.Query().Get("file")
		if filename == "" {
			http.Error(w, "missing file parameter", http.StatusBadRequest)
			return
		}

		filepath := fmt.Sprintf("%s/%s", volumePath, filename)
		err := os.Remove(filepath)
		if err != nil {
			http.Error(w, fmt.Sprintf("failed to delete: %v", err), http.StatusInternalServerError)
			return
		}

		hostname, _ := os.Hostname()
		fmt.Fprintf(w, "deleted %s from task %s\n", filename, hostname)
	})

	http.HandleFunc("/stats", func(w http.ResponseWriter, r *http.Request) {
		entries, _ := os.ReadDir(volumePath)
		var totalSize int64
		for _, entry := range entries {
			info, err := entry.Info()
			if err == nil {
				totalSize += info.Size()
			}
		}

		hostname, _ := os.Hostname()
		fmt.Fprintf(w, "Task: %s\n", hostname)
		fmt.Fprintf(w, "Files: %d\n", len(entries))
		fmt.Fprintf(w, "Total size: %d bytes\n", totalSize)
	})

	http.HandleFunc("/crash", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintln(w, "crashing in 2 seconds...")
		go func() {
			time.Sleep(2 * time.Second)
			os.Exit(1)
		}()

	log.Println("starting server on :8080")
	http.ListenAndServe(":8080", nil)
}
