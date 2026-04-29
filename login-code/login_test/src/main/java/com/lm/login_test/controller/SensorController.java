// com.lm.login_test.controller.SensorController

package com.lm.login_test.controller;

import com.lm.login_test.domain.SensorData;
import com.lm.login_test.service.SensorService;
import com.lm.login_test.utils.Result;
import jakarta.annotation.Resource;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.web.bind.annotation.*;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.List;

@RestController
@RequestMapping("/sensor")
public class SensorController {

    @Resource
    private SensorService sensorService;

    /**
     * 上传温湿度数据
     * POST /sensor/data
     * Body: { "temperature": 25.5, "humidity": 60.0 }
     */
    @PostMapping(value = "/data", consumes = "application/json")
    public Result<SensorData> uploadData(@RequestBody SensorData sensorData) {
        SensorData saved = sensorService.saveSensorData(sensorData);
        return Result.success(saved, "数据上传成功");
    }

    /**
     * 查询所有温湿度数据（倒序）
     * GET /sensor/data
     */
    @GetMapping("/data")
    public Result<List<SensorData>> getAllData() {
        List<SensorData> data = sensorService.getAllSensorData();
        return Result.success(data, "查询成功");
    }

    /**
     * 查询最新一条数据
     * GET /sensor/data/latest
     */
    @GetMapping("/data/latest")
    public Result<SensorData> getLatestData() {
        SensorData data = sensorService.getLatestData();
        if (data != null) {
            return Result.success(data, "获取最新数据成功");
        } else {
            return Result.error("404", "暂无数据");
        }
    }

    /**
     * 查询时间范围内的数据
     * GET /sensor/data/range?start=2025-09-13T10:00:00&end=2025-09-13T18:00:00
     */
    @GetMapping("/data/range")
    public Result<List<SensorData>> getDataInRange(
            @RequestParam @DateTimeFormat(iso = DateTimeFormat.ISO.DATE_TIME) LocalDateTime start,
            @RequestParam @DateTimeFormat(iso = DateTimeFormat.ISO.DATE_TIME) LocalDateTime end) {

        List<SensorData> data = sensorService.getSensorDataByTimeRange(start, end);
        return Result.success(data, "查询成功");
    }

    /**
     * 获取某一天内每2小时的温湿度数据（例如：00:00, 02:00, 04:00 ... 22:00）
     * GET /sensor/data/daily-sampled?date=2025-09-18
     */
    @GetMapping("/data/daily")
    public Result<List<SensorData>> getDailySampledData(
            @RequestParam @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate date) {

        List<SensorData> sampledData = sensorService.getDailySampledData(date);
        return Result.success(sampledData, "查询成功");
    }
}