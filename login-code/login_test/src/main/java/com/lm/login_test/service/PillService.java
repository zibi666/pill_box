package com.lm.login_test.service;

import com.lm.login_test.dto.MedicineRequest;
import com.lm.login_test.dto.PillDTO;
import com.lm.login_test.dto.TodayPillScheduleResponse;

import java.time.LocalDate;
import java.util.List;
import java.util.Map;

public interface PillService {
    void addPill(MedicineRequest request, Long userId) throws Exception;

    void deletePillByUserIdAndMedicineName(Long userId, String medicineName) throws Exception;

    List<PillDTO> getPillsByUserId(Long userId) throws Exception;

    TodayPillScheduleResponse getTodayPillSchedule(Long userId, LocalDate date) throws Exception;

    void recordEatPill(Long userId, String medicineName, String storageCabinet) throws Exception;

    List<Map<String, Object>> listEatPillRecords(Long userId);

    void deleteEatPillByMedicineName(Long userId, String medicineName);

    Map<String, Object> deductNearestDose(Long userId) throws Exception;

    Map<String, Object> deductCabinetDose(Long userId, String storageCabinet) throws Exception;

    Map<String, Object> deductSelectedCabinetDose(Long userId, String storageCabinet, List<String> medicineNames) throws Exception;
}
