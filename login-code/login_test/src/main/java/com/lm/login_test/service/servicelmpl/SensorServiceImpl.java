package com.lm.login_test.service.servicelmpl;


import com.lm.login_test.domain.SensorData;
import com.lm.login_test.repository.SensorDataRepository;
import com.lm.login_test.service.SensorService;
import org.springframework.stereotype.Service;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;

@Service
public class SensorServiceImpl implements SensorService {

    private final SensorDataRepository sensorDataRepository;

    public SensorServiceImpl(SensorDataRepository sensorDataRepository) {
        this.sensorDataRepository = sensorDataRepository;
    }

    @Override
    public SensorData saveSensorData(SensorData data) {
        if (data.getRecordTime() == null) {
            data.setRecordTime(LocalDateTime.now());
        }
        return sensorDataRepository.save(data);
    }

    @Override
    public List<SensorData> getAllSensorData() {
        return sensorDataRepository.findAllByOrderByRecordTimeDesc();
    }

    @Override
    public List<SensorData> getSensorDataByTimeRange(LocalDateTime start, LocalDateTime end) {
        return sensorDataRepository.findByRecordTimeBetween(start, end);
    }

    @Override
    public SensorData getLatestData() {
        List<SensorData> list = sensorDataRepository.findLatest();
        return list.isEmpty() ? null : list.get(0);
    }

    public List<SensorData> getDailySampledData(LocalDate date) {
        LocalDateTime startOfDay = date.atStartOfDay();
        LocalDateTime endOfDay = date.plusDays(1).atStartOfDay();

        // 获取全天数据，按时间升序
        List<SensorData> allData = sensorDataRepository.findByRecordTimeBetweenOrderByRecordTimeAsc(startOfDay, endOfDay);

        List<SensorData> sampled = new ArrayList<>();

        for (int hour = 0; hour < 24; hour += 2) {
            LocalDateTime windowStart = date.atTime(hour, 0);
            LocalDateTime windowEnd = windowStart.plusHours(2);

            // 找这个区间内的第一条数据
            SensorData firstInWindow = allData.stream()
                    .filter(d -> !d.getRecordTime().isBefore(windowStart) && d.getRecordTime().isBefore(windowEnd))
                    .findFirst()
                    .orElse(null);

            if (firstInWindow != null) {
                sampled.add(firstInWindow);
            } else {
                //无数据时填充默认值
                SensorData defaultData = new SensorData();
                defaultData.setTemperature(0.0);
                defaultData.setHumidity(0.0);
                defaultData.setRecordTime(windowStart); // 时间设为窗口开始时间，如 08:00:00
                // ID 可以不设，前端也不需要
                sampled.add(defaultData);
            }
        }

        return sampled;
    }
}