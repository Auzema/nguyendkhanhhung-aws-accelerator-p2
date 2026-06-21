# Tài Liệu Chuyên Sâu: Nền Tảng Quan Sát (Observability) - Tiêu Chuẩn OpenTelemetry & Phương Pháp Cảnh Báo Burn Rate

---

## Phần 1: Câu Chuyện Thực Tế — Bệnh Mù Hệ Thống & Hội Chứng Mệt Mỏi Vì Cảnh Báo Rác

Sau khi đã hoàn thành đường ống CI/CD tự động bằng GitOps, dự án X-Shop tự tin mở rộng hệ thống lên quy mô 30 Pods (Nhóm vùng chứa) chạy song song. Thế nhưng, độ phức tạp của vi dịch vụ (Microservices) lại kéo theo hai cơn ác mộng mới cho Nam và Hoa trong quá trình vận hành:

1.  **Hội chứng mù hệ thống (Lack of Observability)**: Khách hàng gửi vé hỗ trợ phàn nàn rằng chức năng "Thanh toán giỏ hàng" thỉnh thoảng xoay tròn 15 giây rồi báo lỗi mạng. Nam và Hoa phải dùng kết nối từ xa (SSH - Secure Shell) vào từng Pod, gõ lệnh `kubectl logs` để rà soát hàng ngàn dòng nhật ký (Logs). Họ mất trọn một buổi sáng chỉ để tìm ra nguyên nhân: Dịch vụ Thanh toán bị kẹt vì phải chờ phản hồi từ Dịch vụ Kho hàng quá lâu.
2.  **Hội chứng mệt mỏi vì cảnh báo (Alert Fatigue)**: Để chủ động phát hiện lỗi, Nam thiết lập các quy tắc cảnh báo hạ tầng tĩnh: *"Nếu CPU của máy chủ > 80% hoặc Tỷ lệ lỗi > 1% thì lập tức gửi tin nhắn SMS cảnh báo"*. Hậu quả là cứ đến 1 giờ sáng, khi tiến trình dọn dẹp bộ nhớ đệm (Cache eviction) tự động chạy, CPU tăng vọt trong 2 phút rồi hạ xuống, điện thoại của Nam lại đổ chuông. Sau một tuần bị "khủng bố" bởi hàng chục cảnh báo rác, Nam tắt âm thanh thông báo. Vài ngày sau, khi hệ thống thực sự sập do cơ sở dữ liệu rò rỉ kết nối, Nam đã ngủ quên và bỏ qua cảnh báo vì cho rằng đó lại là tin nhắn rác.

Mentor Minh phân tích điểm yếu trong tư duy giám sát cũ:
> *"Giám sát CPU hay RAM là giám sát hạ tầng, không phải giám sát trải nghiệm người dùng. Máy chủ có thể chạy 100% CPU nhưng khách hàng vẫn mua hàng mượt mà, hoặc máy chủ rảnh rỗi nhưng khách hàng lại nhận lỗi 500 do đứt gãy logic mã nguồn. Các em cần chuyển sang mô hình **Giám sát hướng người dùng (User-centric Observability)**, đo lường các Mục Tiêu Chất Lượng Dịch Vụ (SLO - Service Level Objective), và chỉ đánh thức kỹ sư bằng thuật toán **Tốc độ tiêu hao ngân sách lỗi (Burn Rate)**."*

---

## Phần 2: Kiến Trúc Thu Thập Dữ Liệu Với OpenTelemetry (OTel)

Thay vì cài đặt nhiều loại điệp viên (Agents) khác nhau của Datadog, Prometheus, hay Elastic để thu thập dữ liệu, hệ thống hiện đại áp dụng **OpenTelemetry** — một bộ tiêu chuẩn mã nguồn mở hợp nhất cả 3 trụ cột của khả năng quan sát: Số liệu (Metrics), Nhật ký (Logs) và Vết theo dõi phân tán (Traces).

### 1. Phân Tách Trách Nhiệm (SDK vs Collector)

Kiến trúc chuẩn của OTel chia quy trình làm hai phần tách biệt để không làm chậm mã nguồn ứng dụng:

*   **OTel SDK (Thư viện tích hợp trong mã nguồn)**: Lập trình viên nhúng thư viện này vào mã ứng dụng (NodeJS, Java). Nó tự động đo thời gian chạy của hàm, đính kèm mã theo dõi (Trace ID) vào mọi yêu cầu (Request), và đẩy dữ liệu đi cực nhanh thông qua **OTLP (OpenTelemetry Protocol - Giao thức truyền tải viễn trắc chuẩn của OTel)**.
*   **OTel Collector (Trạm thu thập trung gian)**: Hoạt động như một tiến trình độc lập (Sidecar hoặc DaemonSet) trong cụm K8s. Cấu tạo của nó giống một nhà máy xử lý với 3 phân xưởng:
    1.  **Receivers (Cổng nhận)**: Lắng nghe và tiếp nhận dữ liệu OTLP từ SDK.
    2.  **Processors (Xử lý)**: Gộp dữ liệu thành lô (Batching), lọc bỏ thông tin nhạy cảm (như mật khẩu, số thẻ tín dụng), và lấy mẫu (Sampling) để giảm chi phí lưu trữ.
    3.  **Exporters (Xuất xưởng)**: Dịch dữ liệu và đẩy đến các hệ thống lưu trữ đích phù hợp (Đẩy số liệu sang Prometheus, đẩy nhật ký sang Loki, đẩy vết theo dõi sang Jaeger).

### 2. Sơ Đồ Định Tuyến Dữ Liệu
```text
  [ Mã Nguồn X-Shop ]
   (Tích hợp OTel SDK)
          │
          ▼ (Truyền tải cực nhanh qua grpc/OTLP)
  [ OTel Collector ]  ◄── (Thực hiện Batching và Lọc dữ liệu)
          │
      ┌───┼───┐
      ▼   ▼   ▼
 [Prometheus] [Loki] [Jaeger] ──► [ Nền Tảng Hiển Thị Grafana ]
  (Metrics)   (Logs) (Traces)
```

---

## Phần 3: Phương Pháp Luận SLI/SLO Theo Tiêu Chuẩn SRE Google

Mọi hệ thống đều có lúc gặp sự cố. Mục tiêu của SRE không phải là thời gian hoạt động (Uptime) $100\%$, mà là đạt mức độ khả dụng vừa đủ để người dùng hài lòng, đồng thời chừa lại không gian (Ngân sách lỗi) cho việc phát hành tính năng mới.

### 1. Các Khái Niệm Nền Tảng
*   **SLI (Service Level Indicator - Chỉ báo chất lượng dịch vụ)**: Con số toán học khách quan đo lường hệ thống hiện tại.
    *   *Công thức*: $\text{Số lượng sự kiện TỐT} / \text{Tổng số sự kiện} \times 100\%$
*   **SLO (Service Level Objective - Mục tiêu chất lượng dịch vụ)**: Đích đến do bộ phận kinh doanh và kỹ thuật cùng thống nhất (Ví dụ: Ứng dụng phải đạt SLO $99.9\%$).
*   **SLA (Service Level Agreement - Cam kết chất lượng dịch vụ)**: Hợp đồng pháp lý với khách hàng, có điều khoản đền bù tiền nếu hệ thống thấp hơn mức cam kết. (Thường SLA sẽ thấp hơn SLO, ví dụ SLO nội bộ là $99.9\%$, nhưng SLA với khách chỉ là $99.0\%$).

### 2. Hai SLI Cốt Lõi Phải Đo Lường
*   **Độ khả dụng (Availability)**: Tỷ lệ yêu cầu hoàn thành mà không bị lỗi hệ thống.
    *   *Mục tiêu (SLO)*: $99.5\%$ (Nghĩa là trong $1000$ request, cho phép thất bại $5$ request).
*   **Độ trễ (Latency)**: Khả năng phản hồi nhanh chóng (Performance).
    *   *Mục tiêu (SLO)*: $90\%$ số yêu cầu phải được phản hồi trong dưới $200\text{ms}$.

---

## Phần 4: Thuật Toán Cảnh Báo Theo Tốc Độ Đốt Ngân Sách Lỗi (Burn Rate Alert)

Khi chốt SLO là $99.5\%$, hệ thống của chúng ta có **Ngân sách lỗi (Error Budget)** là $0.5\%$. Trong chu kỳ 30 ngày ($720$ giờ), nếu ứng dụng vượt quá $0.5\%$ lỗi, SRE phải đình chỉ mọi tính năng mới để tập trung vá lỗi.

Thay vì cảnh báo ngưỡng tĩnh, hệ thống sẽ đo lường **Tốc độ đốt ngân sách (Burn Rate)**:
*   Nếu $\text{Burn Rate} = 1$: Ta sẽ xài cạn sạch quỹ lỗi trong đúng 30 ngày (Trạng thái ổn định).
*   Nếu $\text{Burn Rate} = 10$: Tốc độ lỗi đang gấp 10 lần cho phép, ta sẽ xài sạch quỹ lỗi chỉ trong 3 ngày!

### 1. Sự Yếu Kém Của Cảnh Báo Khung Thời Gian Đơn Nhất
*   **Khung thời gian ngắn (Ví dụ 5 phút)**: Báo động rất nhanh, nhưng nhạy cảm quá mức. Chỉ cần mạng chậm chập chờn trong 2 phút là hệ thống báo động, dù quỹ lỗi tổng thể chưa bị suy suyển bao nhiêu.
*   **Khung thời gian dài (Ví dụ 12 giờ)**: Cảnh báo cực kỳ chính xác các sự cố suy thoái từ từ. Tuy nhiên, thời gian phát hiện quá lâu. Khi kỹ sư nhận được tin nhắn thì hệ thống đã sập được vài giờ.

### 2. Thuật Toán Cảnh Báo Đa Khung Thời Gian (Multi-Window Alerting)
Kỹ thuật cao cấp nhất hiện nay là so sánh đồng thời hai khung thời gian. Cảnh báo chỉ được phép phát ra khi cả khung thời gian dài VÀ khung thời gian ngắn đều báo vi phạm.

#### **Cảnh báo khẩn cấp (Fast Burn Rate) - Đánh thức kỹ sư ngay lập tức**
Phát hiện sự cố sập diện rộng (Ví dụ đứt kết nối Database).
*   **Khung thời gian dài**: 1 Giờ (Xem xét xu hướng).
*   **Khung thời gian ngắn**: 5 Phút (Xác nhận tình trạng lỗi hiện tại vẫn đang tiếp diễn).
*   **Ngưỡng Burn Rate**: $14.4\text{x}$ (Tiêu hao $2\%$ ngân sách lỗi trong 1 giờ).
*   *Quy trình*: Nếu tỷ lệ lỗi trung bình trong 1 giờ $> 14.4$ lần **VÀ** 5 phút gần nhất vẫn $> 14.4$ lần $\rightarrow$ Hệ thống đang bị hủy hoại cực nhanh. Gửi cuộc gọi khẩn cấp (Page) cho kỹ sư trực.

#### **Cảnh báo suy thoái (Slow Burn Rate) - Xử lý trong giờ làm việc**
Phát hiện lỗi rò rỉ âm ỉ (Ví dụ: Một truy vấn API thi thoảng bị quá tải, gây lỗi lác đác).
*   **Khung thời gian dài**: 6 Giờ.
*   **Khung thời gian ngắn**: 30 Phút.
*   **Ngưỡng Burn Rate**: $6.0\text{x}$ (Tiêu hao $5\%$ ngân sách lỗi trong 6 giờ).
*   *Quy trình*: Hệ thống chưa sập ngay, nhưng đang chảy máu từ từ. Gửi tin nhắn Slack hoặc tạo thẻ Jira để nhóm kỹ thuật ưu tiên điều tra vào sáng hôm sau.

---

## Phần 5: Truy Vấn Prometheus Thực Tế (PromQL)

Dưới đây là đoạn mã thực tế sử dụng **PromQL (Prometheus Query Language - Ngôn ngữ truy vấn của Prometheus)** để thiết lập cảnh báo Fast Burn Rate (14.4x) cho SLO 99.5% (Ngân sách lỗi 0.005).

```yaml
groups:
  - name: XShop_BurnRate_Alerts
    rules:
      - alert: FastBurnRate_PageSRE
        # Biểu thức kiểm tra đồng thời cả khung 1h và khung 5m
        expr: |
          (
            sum(rate(http_requests_total{status=~"5.."}[1h])) 
            / sum(rate(http_requests_total[1h])) 
            > (14.4 * 0.005)
          )
          and
          (
            sum(rate(http_requests_total{status=~"5.."}[5m])) 
            / sum(rate(http_requests_total[5m])) 
            > (14.4 * 0.005)
          )
        for: 2m # Bắt buộc lỗi phải duy trì ít nhất 2 phút để tránh biến động ảo
        labels:
          severity: critical # Đánh dấu mức độ nghiêm trọng
        annotations:
          summary: "Tốc độ lỗi nghiêm trọng: Tiêu thụ 2% Error Budget mỗi giờ!"
          description: "Ngân sách lỗi của ứng dụng đang bị đốt cháy quá mức cho phép với hệ số > 14.4x."
```

Bằng việc kết hợp OpenTelemetry tiêu chuẩn và thuật toán Burn Rate đa khung, dự án X-Shop giải quyết dứt điểm vấn nạn cảnh báo rác, cho phép hệ thống "tự nói" chính xác khi nào nó cần sự giúp đỡ của con người.
