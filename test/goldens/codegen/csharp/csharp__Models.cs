// สร้างโดย NSL Nebular จากโปรเจกต์ "untitled" — ไม่มีวันที่เพื่อให้ diff ใน git อ่านง่าย
using System;
using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

/// <summary>ลูกค้า</summary>
[Table("customers")]
public class Customer
{
    [Key]
    [DatabaseGenerated(DatabaseGeneratedOption.Identity)]
    [Column("id")]
    public long Id { get; set; }

    [MaxLength(120)]
    [Column("email")]
    [Required]
    public string Email { get; set; }

    [Column("created_at")]
    public DateTime? CreatedAt { get; set; }
}

[Table("orders")]
public class Order
{
    [Key]
    [DatabaseGenerated(DatabaseGeneratedOption.Identity)]
    [Column("id")]
    public long Id { get; set; }

    [Column("customer_id")]
    public long CustomerId { get; set; }

    /// <summary>สถานะ</summary>
    [MaxLength(20)]
    [Column("status")]
    [Required]
    public string Status { get; set; }

    [Column(TypeName = "decimal(10,2)")]
    [Column("total")]
    public decimal? Total { get; set; }
}
