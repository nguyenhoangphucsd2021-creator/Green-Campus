# Cấu hình Supabase

1. Tạo dự án Supabase miễn phí.
2. Mở SQL Editor và chạy toàn bộ `schema.sql`.
3. Tạo người dùng quản trị trong Authentication → Users.
4. Lấy UUID người dùng và chạy câu lệnh cuối file SQL để cấp vai trò `admin`.
5. Cấu hình `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` trong Netlify environment variables. Service-role key chỉ đặt phía máy chủ, tuyệt đối không đưa vào frontend.
6. Cấu hình nguồn RSS/Atom HTTPS đã được kiểm tra trong `GC_FEED_URLS`.

Bảng `content_items` chỉ công khai bản ghi có `status='published'`. Bộ thu thập theo lịch chỉ tạo `pending_review`, tránh tự động phát tán thông tin chưa được kiểm chứng.

## Eco Challenge Cloud V2 (đăng nhập, nhiệm vụ ảnh, điểm tài khoản, cây xanh)

1. Chạy `schema.sql` trước, sau đó chạy toàn bộ `eco-cloud-v2.sql` trong SQL Editor.
2. Tạo tài khoản quản trị tại Authentication → Users (hoặc đăng ký tại trang game). Lấy UUID và cấp vai trò:
   `update public.profiles set role='admin' where id='UUID_TAI_KHOAN';`
3. Điền `supabaseUrl` và `supabaseAnonKey` trong `public-config.js`. Chỉ dùng anon key ở frontend; tuyệt đối không đưa service-role key vào HTML/JS.
4. Đăng nhập tại Eco Challenge. Người chơi đăng ký bằng email + mật khẩu; nếu bật xác nhận email thì cần bấm liên kết trong thư trước khi đăng nhập.
5. Quản trị viên vào `admin.html` để đăng nhiệm vụ ảnh, ẩn nhiệm vụ và cộng/trừ điểm. Nhiệm vụ được lưu ở Supabase Storage + `eco_daily_tasks`, hiển thị cho mọi tài khoản đã đăng nhập.

**Cân bằng cây xanh do máy chủ thực thi:** trồng cây −20 điểm; tưới tối đa 2 lần (mỗi lần −5 điểm, rút ngắn 6 giờ); trưởng thành sau 24 giờ tự nhiên, tối thiểu 12 giờ nếu tưới đủ 2 lần; thu hoạch +40 điểm. Khi dùng đủ hai lượt tưới, chu kỳ có lãi +10 điểm. Không có trường nhập số điểm ở phía người chơi; RPC kiểm tra số dư và thời gian ở PostgreSQL.

Mọi cộng/trừ điểm quản trị được ghi thành dòng mới trong `eco_account_ledger`, kèm tài khoản quản trị, thời gian và lý do; số dư không được âm. Bảng xếp hạng đọc từ view chung `eco_public_leaderboard`.
