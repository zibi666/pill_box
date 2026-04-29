ALTER TABLE `pill_manage`
  ADD COLUMN `total_pills` DECIMAL(10,2) NULL COMMENT '总片数' AFTER `dosage_frequency`,
  ADD COLUMN `pills_per_intake` DECIMAL(10,2) NULL COMMENT '每次服药多少片' AFTER `total_pills`;

-- 如果你希望给旧数据补默认值，可以取消下面两行注释后执行：
-- UPDATE `pill_manage` SET `total_pills` = 30 WHERE `total_pills` IS NULL;
-- UPDATE `pill_manage` SET `pills_per_intake` = 1.00 WHERE `pills_per_intake` IS NULL;

-- 如果你补完旧数据后想改成必填字段，可以继续执行：
-- ALTER TABLE `pill_manage`
--   MODIFY COLUMN `total_pills` DECIMAL(10,2) NOT NULL COMMENT '总片数',
--   MODIFY COLUMN `pills_per_intake` DECIMAL(10,2) NOT NULL COMMENT '每次服药多少片';
