package com.lm.login_test.repository;



import com.lm.login_test.domain.SensorData;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.stereotype.Repository;

import java.time.LocalDateTime;
import java.util.List;

@Repository
public interface SensorDataRepository extends JpaRepository<SensorData, Long> {

    // 查询所有数据（按时间倒序）
    List<SensorData> findAllByOrderByRecordTimeDesc();

    // 查询时间范围内的数据
    List<SensorData> findByRecordTimeBetween(LocalDateTime start, LocalDateTime end);
    List<SensorData> findByRecordTimeBetweenOrderByRecordTimeAsc(LocalDateTime start, LocalDateTime end);
    // 查询最新一条数据
    @Query("SELECT s FROM SensorData s ORDER BY s.recordTime DESC")
    List<SensorData> findLatest();

}