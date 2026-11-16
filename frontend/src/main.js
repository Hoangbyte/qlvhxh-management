import "./style.css";

const apiBaseUrl = (
  import.meta.env.VITE_API_BASE_URL || "http://localhost:8080"
).replace(/\/+$/, "");
const statusElement = document.querySelector("#connection-status");
const checkButton = document.querySelector("#check-connection");

function showStatus(state, message) {
  statusElement.className = `status status-${state}`;
  statusElement.textContent = message;
}

async function checkConnection() {
  checkButton.disabled = true;
  showStatus("pending", "Đang kiểm tra kết nối...");

  let response;
  try {
    response = await fetch(`${apiBaseUrl}/api/health`);
  } catch {
    showStatus(
      "error",
      "Trình duyệt không gọi được backend. Hãy kiểm tra server và cấu hình CORS.",
    );
    checkButton.disabled = false;
    return;
  }

  if (response.status === 503) {
    showStatus(
      "error",
      "Backend trả HTTP 503: không thể kết nối hoặc truy vấn SQL Server.",
    );
    checkButton.disabled = false;
    return;
  }

  if (!response.ok) {
    showStatus(
      "error",
      `Backend phản hồi HTTP ${response.status}; không thể xác nhận kết nối SQL Server.`,
    );
    checkButton.disabled = false;
    return;
  }

  try {
    const result = await response.json();
    if (result.success && result.data?.database === "connected") {
      showStatus("success", "SQL Server đã kết nối.");
    } else {
      showStatus("error", "Backend trả dữ liệu không như mong đợi.");
    }
  } catch {
    showStatus("error", "Backend trả về phản hồi không hợp lệ.");
  }

  checkButton.disabled = false;
}

checkButton.addEventListener("click", checkConnection);
checkConnection();
