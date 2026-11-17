# CircleSwitcher v2.0.0 (3D Hologram Cylinder, Orbital Orbs & Liquid Glass)

## Tính năng nổi bật (v2.0.0)
- **Đầy đủ chế độ 3D & Icon Tròn:**
  - `0`: Vòng Trụ Thẻ 3D (3D Hologram Cylinder — Carousel Cards)
  - `1`: Icon Tròn Vòng Trụ 3D (3D Cylindrical Orbs — Đứng thẳng xoay quanh trụ)
  - `2`: Khung Tròn & Vành Đai Icon (Orbital Preview & Circular Orbs)
  - `3`: Bánh Xe Icon 360° (Radial Ring Wheel)
  - `4–9`: Circle Wheel 3D, 3D Cards, Card Deck, CoverFlow, Inverse CoverFlow, 2D Flat.
- **Xoay vòng tròn 360° vô tận (Infinite Circular Scroll)** không giới hạn ứng dụng.
- **Mở ứng dụng Full màn hình 100%:** Tách biệt hoàn toàn trạng thái Đa nhiệm và Toàn màn hình, tự động trả góc bo và gỡ viền sáng ngay khi chạm mở App.
- **Hiệu ứng Motion Blur:** Nhòe chuyển động mượt mà khi vuốt vào Switcher và sắc nét khi dừng lại.
- **Vị trí Tên App tùy chỉnh:** Phía trên, Ở giữa (tự động làm mờ thẻ theo thanh trượt), Phía dưới hoặc Ẩn, kèm nút đóng nhanh `✕`.
- **Viền Thẻ & Đế Hologram 3D độc lập:** Bật/tắt riêng, chỉnh độ sáng, kích thước và chọn màu Full 16 triệu màu (RGB Color Picker).
- **Cài đặt Song ngữ (Tiếng Việt / English)** kèm **Màn hình Xem trước 3D luôn ghim nổi ở trên (Sticky Live Preview)**.

## Cách build tự động trên GitHub Actions
1. Đẩy toàn bộ các file và thư mục (bao gồm `.github/workflows/build.yml`) lên repository GitHub.
2. Vào tab **Actions** -> chọn **Build CircleSwitcher 2.0.0 (.deb)** -> bấm **Run workflow**.
3. Tải gói `.deb` tại mục **Artifacts**:
   - `CircleSwitcher-2.0.0-Rootless-deb` (iOS 15 - 16.3.1+ Rootless / Dopamine / Palera1n)
   - `CircleSwitcher-2.0.0-Rootful-deb` (iOS 14 - 15 Rootful)
