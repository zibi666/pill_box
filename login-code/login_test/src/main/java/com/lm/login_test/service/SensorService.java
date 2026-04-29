package com.lm.login_test.service;

import com.lm.login_test.domain.SensorData;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.List;

public interface SensorService {
    SensorData saveSensorData(SensorData data);
    List<SensorData> getAllSensorData();
    List<SensorData> getSensorDataByTimeRange(LocalDateTime start, LocalDateTime end);
    SensorData getLatestData(); // 获取最新一条

    List<SensorData> getDailySampledData(LocalDate date);


}
