// สร้างโดย NSL Nebular จากโปรเจกต์ "untitled" — ไม่มีวันที่เพื่อให้ diff ใน git อ่านง่าย
import jakarta.persistence.*;

/** ลูกค้า */
@Entity
@Table(name = "customers")
public class Customer {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "id", nullable = false)
    private long id;

    @Column(name = "email", nullable = false, unique = true, length = 120)
    private String email;

    @Column(name = "created_at")
    private java.time.Instant createdAt;

    public long getId() { return id; }
    public void setId(long id) { this.id = id; }

    public String getEmail() { return email; }
    public void setEmail(String email) { this.email = email; }

    public java.time.Instant getCreatedAt() { return createdAt; }
    public void setCreatedAt(java.time.Instant createdAt) { this.createdAt = createdAt; }
}

@Entity
@Table(name = "orders")
public class Order {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "id", nullable = false)
    private long id;

    @Column(name = "customer_id", nullable = false)
    private long customerId;

    /** สถานะ */
    @Column(name = "status", nullable = false, length = 20)
    private String status;

    @Column(name = "total", precision = 10, scale = 2)
    private java.math.BigDecimal total;

    public long getId() { return id; }
    public void setId(long id) { this.id = id; }

    public long getCustomerId() { return customerId; }
    public void setCustomerId(long customerId) { this.customerId = customerId; }

    public String getStatus() { return status; }
    public void setStatus(String status) { this.status = status; }

    public java.math.BigDecimal getTotal() { return total; }
    public void setTotal(java.math.BigDecimal total) { this.total = total; }
}
