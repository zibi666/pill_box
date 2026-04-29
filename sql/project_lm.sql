/*
 Navicat Premium Dump SQL

 Source Server         : 李宓数据库
 Source Server Type    : MySQL
 Source Server Version : 50718 (5.7.18-cynos-2.1.13-log)
 Source Host           : sh-cynosdbmysql-grp-2gf1ewak.sql.tencentcdb.com:28451
 Source Schema         : project_lm

 Target Server Type    : MySQL
 Target Server Version : 50718 (5.7.18-cynos-2.1.13-log)
 File Encoding         : 65001

 Date: 23/04/2026 13:30:31
*/

SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;

-- ----------------------------
-- Table structure for eat_pill
-- ----------------------------
DROP TABLE IF EXISTS `eat_pill`;
CREATE TABLE `eat_pill`  (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `medicine_name` varchar(255) CHARACTER SET utf8 COLLATE utf8_general_ci NOT NULL,
  `intake_times` text CHARACTER SET utf8 COLLATE utf8_general_ci NOT NULL,
  `storage_cabinet` varchar(255) CHARACTER SET utf8 COLLATE utf8_general_ci NOT NULL,
  PRIMARY KEY (`id`) USING BTREE
) ENGINE = InnoDB AUTO_INCREMENT = 105 CHARACTER SET = utf8 COLLATE = utf8_general_ci ROW_FORMAT = Dynamic;



-- ----------------------------
-- Table structure for employee
-- ----------------------------
DROP TABLE IF EXISTS `employee`;
CREATE TABLE `employee`  (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `name` varchar(255) CHARACTER SET utf8 COLLATE utf8_general_ci NULL DEFAULT NULL,
  `sex` varchar(255) CHARACTER SET utf8 COLLATE utf8_general_ci NULL DEFAULT NULL,
  `no` varchar(255) CHARACTER SET utf8 COLLATE utf8_general_ci NULL DEFAULT NULL,
  `age` int(11) NULL DEFAULT NULL,
  `description` varchar(255) CHARACTER SET utf8 COLLATE utf8_general_ci NULL DEFAULT NULL,
  `department_id` int(11) NULL DEFAULT NULL,
  PRIMARY KEY (`id`) USING BTREE
) ENGINE = InnoDB AUTO_INCREMENT = 17 CHARACTER SET = utf8 COLLATE = utf8_general_ci ROW_FORMAT = Dynamic;



-- ----------------------------
-- Table structure for entry_records
-- ----------------------------
DROP TABLE IF EXISTS `entry_records`;
CREATE TABLE `entry_records`  (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `image` varchar(255) CHARACTER SET utf8 COLLATE utf8_general_ci NULL DEFAULT NULL,
  `etime` datetime NULL DEFAULT NULL,
  PRIMARY KEY (`id`) USING BTREE
) ENGINE = InnoDB AUTO_INCREMENT = 719130047 CHARACTER SET = utf8 COLLATE = utf8_general_ci ROW_FORMAT = Dynamic;



-- ----------------------------
-- Table structure for login_test
-- ----------------------------
DROP TABLE IF EXISTS `login_test`;
CREATE TABLE `login_test`  (
  `uid` int(11) NOT NULL AUTO_INCREMENT,
  `uname` varchar(255) CHARACTER SET utf8 COLLATE utf8_general_ci NOT NULL,
  `password` varchar(255) CHARACTER SET utf8 COLLATE utf8_general_ci NOT NULL,
  PRIMARY KEY (`uid`) USING BTREE
) ENGINE = InnoDB AUTO_INCREMENT = 6 CHARACTER SET = utf8 COLLATE = utf8_general_ci ROW_FORMAT = Dynamic;



-- ----------------------------
-- Table structure for pill_manage
-- ----------------------------
DROP TABLE IF EXISTS `pill_manage`;
CREATE TABLE `pill_manage`  (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `medicine_name` varchar(255) CHARACTER SET utf8 COLLATE utf8_general_ci NOT NULL,
  `dosage_frequency` int(11) NOT NULL,
  `total_pills` int(11) NULL DEFAULT NULL COMMENT '总片数',
  `pills_per_intake` decimal(6, 2) NULL DEFAULT NULL COMMENT '每次服药多少片',
  `intake_times` text CHARACTER SET utf8 COLLATE utf8_general_ci NOT NULL,
  `user_id` int(11) NOT NULL,
  `medicine_category` varchar(255) CHARACTER SET utf8 COLLATE utf8_general_ci NOT NULL,
  `expiry_date` datetime NULL DEFAULT NULL,
  PRIMARY KEY (`id`) USING BTREE,
  INDEX `fk_pill_user`(`user_id`) USING BTREE,
  CONSTRAINT `fk_pill_user` FOREIGN KEY (`user_id`) REFERENCES `login_test` (`uid`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE = InnoDB AUTO_INCREMENT = 92 CHARACTER SET = utf8 COLLATE = utf8_general_ci ROW_FORMAT = Dynamic;


-- ----------------------------
-- Table structure for record
-- ----------------------------
DROP TABLE IF EXISTS `record`;
CREATE TABLE `record`  (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `open_time` datetime NOT NULL,
  PRIMARY KEY (`id`) USING BTREE
) ENGINE = InnoDB AUTO_INCREMENT = 141 CHARACTER SET = utf8 COLLATE = utf8_general_ci ROW_FORMAT = Dynamic;



-- ----------------------------
-- Table structure for sensor_data
-- ----------------------------
DROP TABLE IF EXISTS `sensor_data`;
CREATE TABLE `sensor_data`  (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `temperature` double NOT NULL,
  `humidity` double NOT NULL,
  `record_time` datetime NOT NULL,
  PRIMARY KEY (`id`) USING BTREE
) ENGINE = InnoDB AUTO_INCREMENT = 6134 CHARACTER SET = utf8 COLLATE = utf8_general_ci ROW_FORMAT = Dynamic;



SET FOREIGN_KEY_CHECKS = 1;
