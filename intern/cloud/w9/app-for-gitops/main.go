// media-app: upload + view images/gifs/videos. Files stored in AWS S3.
// Single Go binary: serves the HTML/JS UI and a small REST API.
package main

import (
	"context"
	"encoding/json"
	_ "embed"
	"log"
	"net/http"
	"os"
	"path"
	"strconv"
	"strings"
	"time"

	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/feature/s3/manager"
	"github.com/aws/aws-sdk-go-v2/service/s3"
)

//go:embed static/index.html
var indexHTML []byte

const (
	maxUpload     = 100 << 20 // 100 MB
	presignExpiry = time.Hour
)

var (
	bucket   string
	s3client *s3.Client
	uploader *manager.Uploader
	presign  *s3.PresignClient
)

// item is one media object returned to the browser.
type item struct {
	Key  string `json:"key"`
	URL  string `json:"url"`
	Size int64  `json:"size"`
}

func main() {
	bucket = mustEnv("S3_BUCKET")
	region := mustEnv("AWS_REGION")

	cfg, err := config.LoadDefaultConfig(context.Background(), config.WithRegion(region))
	if err != nil {
		log.Fatalf("load aws config: %v", err)
	}
	s3client = s3.NewFromConfig(cfg)
	uploader = manager.NewUploader(s3client)
	presign = s3.NewPresignClient(s3client)

	mux := http.NewServeMux()
	mux.HandleFunc("GET /", serveIndex)
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, _ *http.Request) { w.Write([]byte("ok")) })
	mux.HandleFunc("POST /api/upload", handleUpload)
	mux.HandleFunc("GET /api/list", handleList)
	mux.HandleFunc("DELETE /api/item", handleDelete)

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	log.Printf("media-app listening on :%s (bucket=%s region=%s)", port, bucket, region)
	log.Fatal(http.ListenAndServe(":"+port, mux))
}

func mustEnv(k string) string {
	v := os.Getenv(k)
	if v == "" {
		log.Fatalf("missing required env %s", k)
	}
	return v
}

func serveIndex(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Write(indexHTML)
}

func handleUpload(w http.ResponseWriter, r *http.Request) {
	r.Body = http.MaxBytesReader(w, r.Body, maxUpload)
	if err := r.ParseMultipartForm(32 << 20); err != nil {
		httpErr(w, http.StatusBadRequest, "file too large or bad form (max 100MB)")
		return
	}
	file, header, err := r.FormFile("file")
	if err != nil {
		httpErr(w, http.StatusBadRequest, "missing 'file' field")
		return
	}
	defer file.Close()

	ct := header.Header.Get("Content-Type")
	if !strings.HasPrefix(ct, "image/") && !strings.HasPrefix(ct, "video/") {
		httpErr(w, http.StatusUnsupportedMediaType, "only image/* and video/* allowed")
		return
	}

	// Key: <unixnano>-<sanitized-name> to avoid collisions.
	name := path.Base(strings.ReplaceAll(header.Filename, "/", "_"))
	key := strconv.FormatInt(time.Now().UnixNano(), 10) + "-" + name

	_, err = uploader.Upload(r.Context(), &s3.PutObjectInput{
		Bucket:      &bucket,
		Key:         &key,
		Body:        file,
		ContentType: &ct,
	})
	if err != nil {
		log.Printf("upload error: %v", err)
		httpErr(w, http.StatusBadGateway, "upload to S3 failed")
		return
	}
	writeJSON(w, map[string]string{"key": key})
}

func handleList(w http.ResponseWriter, r *http.Request) {
	out, err := s3client.ListObjectsV2(r.Context(), &s3.ListObjectsV2Input{Bucket: &bucket})
	if err != nil {
		log.Printf("list error: %v", err)
		httpErr(w, http.StatusBadGateway, "list S3 failed")
		return
	}
	items := make([]item, 0, len(out.Contents))
	for _, obj := range out.Contents {
		req, err := presign.PresignGetObject(r.Context(), &s3.GetObjectInput{
			Bucket: &bucket,
			Key:    obj.Key,
		}, s3.WithPresignExpires(presignExpiry))
		if err != nil {
			continue
		}
		var size int64
		if obj.Size != nil {
			size = *obj.Size
		}
		items = append(items, item{Key: *obj.Key, URL: req.URL, Size: size})
	}
	writeJSON(w, items)
}

func handleDelete(w http.ResponseWriter, r *http.Request) {
	key := r.URL.Query().Get("key")
	if key == "" {
		httpErr(w, http.StatusBadRequest, "missing 'key' query param")
		return
	}
	_, err := s3client.DeleteObject(r.Context(), &s3.DeleteObjectInput{Bucket: &bucket, Key: &key})
	if err != nil {
		log.Printf("delete error: %v", err)
		httpErr(w, http.StatusBadGateway, "delete from S3 failed")
		return
	}
	writeJSON(w, map[string]string{"deleted": key})
}

func writeJSON(w http.ResponseWriter, v any) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(v)
}

func httpErr(w http.ResponseWriter, code int, msg string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	json.NewEncoder(w).Encode(map[string]string{"error": msg})
}
