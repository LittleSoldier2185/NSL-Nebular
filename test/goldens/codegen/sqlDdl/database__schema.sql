-- untitled (MySQL / MariaDB) — สร้างโดย NSL Nebular

CREATE TABLE `customers` (
  `id` BIGINT NOT NULL AUTO_INCREMENT,
  `email` VARCHAR(120) NOT NULL UNIQUE,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='ลูกค้า';

CREATE TABLE `orders` (
  `id` BIGINT NOT NULL AUTO_INCREMENT,
  `customer_id` BIGINT NOT NULL,
  `status` VARCHAR(20) NOT NULL DEFAULT 'pending' COMMENT 'สถานะ',
  `total` DECIMAL(10,2),
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE INDEX `idx_orders_status` ON `orders` (`status`);

ALTER TABLE `orders` ADD CONSTRAINT `fk_orders_customer_id` FOREIGN KEY (`customer_id`) REFERENCES `customers` (`id`) ON DELETE CASCADE;
