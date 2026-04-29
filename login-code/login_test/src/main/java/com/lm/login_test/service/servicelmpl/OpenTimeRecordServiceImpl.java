package com.lm.login_test.service.servicelmpl;

import com.lm.login_test.domain.OpenTimeRecord;
import com.lm.login_test.dto.TodayOpenTimeRecordResponse;
import com.lm.login_test.repository.OpenTimeRecordDao;
import com.lm.login_test.service.OpenTimeRecordService;
import jakarta.annotation.Resource;
import org.springframework.stereotype.Service;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.List;

@Service
public class OpenTimeRecordServiceImpl implements OpenTimeRecordService {

    @Resource
    private OpenTimeRecordDao openTimeRecordDao;

    @Override
    public OpenTimeRecord saveOpenTime(OpenTimeRecord record) {
        return openTimeRecordDao.save(record);
    }

    @Override
    public List<OpenTimeRecord> getAllOpenTimes() {
        return openTimeRecordDao.findAll();
    }

    @Override
    public OpenTimeRecord getOpenTimeById(Long id) {
        return openTimeRecordDao.findById(id).orElse(null);
    }

    @Override
    public void deleteOpenTimeById(Long id) {
        openTimeRecordDao.deleteById(id);
    }

    @Override
    public TodayOpenTimeRecordResponse getOpenTimesByDate(LocalDate date) {
        LocalDate queryDate = date == null ? LocalDate.now() : date;
        LocalDateTime startTime = queryDate.atStartOfDay();
        LocalDateTime endTime = queryDate.plusDays(1).atStartOfDay();
        List<OpenTimeRecord> records =
                openTimeRecordDao.findByOpenTimeGreaterThanEqualAndOpenTimeLessThanOrderByOpenTimeAsc(startTime, endTime);
        return new TodayOpenTimeRecordResponse(queryDate, startTime, endTime, records.size(), records);
    }
}
