package com.lm.login_test.controller;

import com.lm.login_test.domain.OpenTimeRecord;
import com.lm.login_test.dto.TodayOpenTimeRecordResponse;
import com.lm.login_test.service.OpenTimeRecordService;
import com.lm.login_test.utils.Result;
import jakarta.annotation.Resource;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.time.LocalDate;
import java.util.List;

@RestController
@RequestMapping("/api/open-time")
public class OpenTimeRecordController {

    @Resource
    private OpenTimeRecordService openTimeRecordService;

    @PostMapping("/add")
    public Result<OpenTimeRecord> addOpenTime(@RequestBody OpenTimeRecord record) {
        try {
            OpenTimeRecord saved = openTimeRecordService.saveOpenTime(record);
            return Result.success(saved, "open time saved");
        } catch (Exception e) {
            return Result.error("500", "save failed: " + e.getMessage());
        }
    }

    @GetMapping("/list")
    public Result<List<OpenTimeRecord>> getAllOpenTimes() {
        List<OpenTimeRecord> records = openTimeRecordService.getAllOpenTimes();
        return Result.success(records, "query success");
    }

    @GetMapping("/today")
    public Result<TodayOpenTimeRecordResponse> getTodayOpenTimes(
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate date) {
        TodayOpenTimeRecordResponse response = openTimeRecordService.getOpenTimesByDate(date);
        return Result.success(response, "query success");
    }

    @GetMapping("/{id}")
    public Result<OpenTimeRecord> getOpenTimeById(@PathVariable Long id) {
        OpenTimeRecord record = openTimeRecordService.getOpenTimeById(id);
        if (record != null) {
            return Result.success(record, "query success");
        } else {
            return Result.error("404", "record not found");
        }
    }

    @DeleteMapping("/{id}")
    public Result<String> deleteOpenTime(@PathVariable Long id) {
        openTimeRecordService.deleteOpenTimeById(id);
        return Result.success("delete success");
    }
}
