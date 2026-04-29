package com.lm.login_test.repository;

import com.lm.login_test.domain.OpenTimeRecord;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.time.LocalDateTime;
import java.util.List;

@Repository
public interface OpenTimeRecordDao extends JpaRepository<OpenTimeRecord, Long> {
    List<OpenTimeRecord> findByOpenTimeGreaterThanEqualAndOpenTimeLessThanOrderByOpenTimeAsc(
            LocalDateTime startTime,
            LocalDateTime endTime
    );
}
