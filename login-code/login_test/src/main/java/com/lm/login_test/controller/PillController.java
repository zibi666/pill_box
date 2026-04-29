package com.lm.login_test.controller;

import com.lm.login_test.dto.MedicineRequest;
import com.lm.login_test.dto.PillDTO;
import com.lm.login_test.service.PillService;
import com.lm.login_test.utils.Result;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.time.LocalDate;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/pill")
public class PillController {

    @Autowired
    private PillService pillService;

    @PostMapping("/add")
    public Result<String> addPill(@RequestBody MedicineRequest request, @RequestParam Long userId) {
        try {
            pillService.addPill(request, userId);
            return Result.success("add success");
        } catch (Exception e) {
            return Result.error("500", "add failed: " + e.getMessage());
        }
    }

    @PostMapping("/delete")
    public Result<String> deletePill(@RequestBody Map<String, Object> payload) {
        Long userId = Long.valueOf(payload.get("userId").toString());
        String medicineName = payload.get("medicineName").toString();

        try {
            pillService.deletePillByUserIdAndMedicineName(userId, medicineName);
            return Result.success("delete success");
        } catch (Exception e) {
            return Result.error("500", "delete failed: " + e.getMessage());
        }
    }

    @GetMapping("/list")
    public Result<List<PillDTO>> listPills(@RequestParam Long userId) {
        try {
            List<PillDTO> pills = pillService.getPillsByUserId(userId);
            return Result.success(pills, "query success");
        } catch (Exception e) {
            return Result.error("500", "query failed: " + e.getMessage());
        }
    }

    @GetMapping("/today")
    public Result<Map<String, Object>> getTodayPillSchedule(
            @RequestParam(required = false) Long userId,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate date) {
        try {
            LocalDate queryDate = date == null ? LocalDate.now() : date;
            List<Map<String, Object>> sourceRecords = pillService.listEatPillRecords(userId);
            List<Map<String, Object>> records = new ArrayList<>();

            for (Map<String, Object> sourceRecord : sourceRecords) {
                Map<String, Object> record = new HashMap<>();
                record.put("medicineName", sourceRecord.get("medicineName"));
                record.put("intakeTimes", sourceRecord.get("intakeTimes"));
                record.put("storageCabinet", sourceRecord.get("storageCabinet"));
                records.add(record);
            }

            Map<String, Object> data = new HashMap<>();
            data.put("date", queryDate);
            data.put("total", records.size());
            data.put("records", records);
            return Result.success(data, "query success");
        } catch (Exception e) {
            return Result.error("500", "query failed: " + e.getMessage());
        }
    }

    @PostMapping("/eat")
    public Result<String> recordEatPill(@RequestParam Long userId, @RequestBody Map<String, String> payload) {
        try {
            String medicineName = payload.get("medicineName");
            String storageCabinet = payload.get("storageCabinet");
            if (medicineName == null || storageCabinet == null) {
                return Result.error("400", "medicineName and storageCabinet are required");
            }
            pillService.recordEatPill(userId, medicineName, storageCabinet);
            return Result.success("save success");
        } catch (Exception e) {
            return Result.error("500", e.getMessage());
        }
    }

    @GetMapping("/eat/list")
    public Result<List<Map<String, Object>>> listEatPillRecords(@RequestParam(required = false) Long userId) {
        try {
            List<Map<String, Object>> records = pillService.listEatPillRecords(userId);
            return Result.success(records, "query success");
        } catch (Exception e) {
            return Result.error("500", "query failed: " + e.getMessage());
        }
    }

    @PostMapping("/eat/delete")
    public Result<String> deleteEatPillRecord(@RequestBody Map<String, Object> payload) {
        Object userIdValue = payload.get("userId");
        String medicineName = payload.get("medicineName") == null ? null : payload.get("medicineName").toString();
        if (medicineName == null || medicineName.trim().isEmpty()) {
            return Result.error("400", "medicineName can not be empty");
        }

        Long userId = null;
        if (userIdValue != null) {
            userId = Long.valueOf(userIdValue.toString());
        }

        try {
            pillService.deleteEatPillByMedicineName(userId, medicineName);
            return Result.success("delete success");
        } catch (Exception e) {
            return Result.error("500", "delete failed: " + e.getMessage());
        }
    }

    @PostMapping("/deduct-nearest-dose")
    public Result<Map<String, Object>> deductNearestDose(@RequestParam Long userId) {
        try {
            Map<String, Object> result = pillService.deductNearestDose(userId);
            return Result.success(result, "deduct success");
        } catch (Exception e) {
            return Result.error("500", "deduct failed: " + e.getMessage());
        }
    }

    @PostMapping("/deduct-cabinet-dose")
    public Result<Map<String, Object>> deductCabinetDose(
            @RequestParam Long userId,
            @RequestParam String storageCabinet) {
        try {
            Map<String, Object> result = pillService.deductCabinetDose(userId, storageCabinet);
            return Result.success(result, "deduct success");
        } catch (Exception e) {
            return Result.error("500", "deduct failed: " + e.getMessage());
        }
    }

    @PostMapping("/deduct-selected-cabinet-dose")
    public Result<Map<String, Object>> deductSelectedCabinetDose(
            @RequestParam Long userId,
            @RequestBody Map<String, Object> payload) {
        try {
            String storageCabinet = payload.get("storageCabinet") == null ? "" : payload.get("storageCabinet").toString();
            Object medicineNamesValue = payload.get("medicineNames");
            List<String> medicineNames = new ArrayList<>();
            if (medicineNamesValue instanceof List<?>) {
                for (Object item : (List<?>) medicineNamesValue) {
                    if (item != null) {
                        medicineNames.add(item.toString());
                    }
                }
            }

            Map<String, Object> result = pillService.deductSelectedCabinetDose(userId, storageCabinet, medicineNames);
            return Result.success(result, "deduct success");
        } catch (Exception e) {
            return Result.error("500", "deduct failed: " + e.getMessage());
        }
    }
}
