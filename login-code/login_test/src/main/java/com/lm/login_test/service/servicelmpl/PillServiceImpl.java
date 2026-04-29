package com.lm.login_test.service.servicelmpl;

import com.lm.login_test.domain.EatPill;
import com.lm.login_test.domain.Pill;
import com.lm.login_test.domain.User;
import com.lm.login_test.dto.MedicineRequest;
import com.lm.login_test.dto.PillDTO;
import com.lm.login_test.dto.TodayPillScheduleItem;
import com.lm.login_test.dto.TodayPillScheduleResponse;
import com.lm.login_test.repository.EatPillRepository;
import com.lm.login_test.repository.PillRepository;
import com.lm.login_test.repository.UserDao;
import com.lm.login_test.service.PillService;
import jakarta.transaction.Transactional;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.LocalTime;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashSet;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.stream.Collectors;

@Service
public class PillServiceImpl implements PillService {
    private static final DateTimeFormatter INPUT_TIME_FORMATTER = DateTimeFormatter.ofPattern("H:mm");
    private static final DateTimeFormatter OUTPUT_TIME_FORMATTER = DateTimeFormatter.ofPattern("HH:mm");
    private static final ZoneId MEDICINE_TIME_ZONE = ZoneId.of("Asia/Shanghai");

    @Autowired
    private PillRepository pillRepository;

    @Autowired
    private UserDao userRepository;

    @Autowired
    private EatPillRepository eatPillRepository;

    @Override
    @Transactional
    public void addPill(MedicineRequest request, Long userId) throws Exception {
        User user = userRepository.findById(userId)
                .orElseThrow(() -> new Exception("user not found"));

        if (request.getMedicineName() == null || request.getMedicineName().trim().isEmpty()) {
            throw new Exception("medicineName can not be empty");
        }
        if (request.getMedicineCategory() == null || request.getMedicineCategory().trim().isEmpty()) {
            throw new Exception("medicineCategory can not be empty");
        }
        if (request.getDosageFrequency() <= 0) {
            throw new Exception("dosageFrequency must be greater than 0");
        }
        if (request.getIntakeTimes() == null || request.getIntakeTimes().length == 0) {
            throw new Exception("intakeTimes can not be empty");
        }
        if (request.getIntakeTimes().length != request.getDosageFrequency()) {
            throw new Exception("dosageFrequency must match intakeTimes length");
        }
        if (request.getTotalPills() == null || request.getTotalPills() <= 0) {
            throw new Exception("totalPills must be greater than 0");
        }
        if (request.getPillsPerIntake() == null || request.getPillsPerIntake() <= 0) {
            throw new Exception("pillsPerIntake must be greater than 0");
        }
        if (request.getPillsPerIntake() > request.getTotalPills()) {
            throw new Exception("pillsPerIntake can not be greater than totalPills");
        }

        String medicineName = request.getMedicineName().trim();
        if (pillRepository.existsByUserAndMedicineName(user, medicineName)) {
            throw new Exception("medicineName already exists");
        }

        Pill pill = new Pill();
        pill.setMedicineName(medicineName);
        pill.setDosageFrequency(request.getDosageFrequency());
        pill.setMedicineCategory(request.getMedicineCategory().trim());
        pill.setExpiryDate(request.getExpiryDate());
        pill.setTotalPills(roundDose(request.getTotalPills()));
        pill.setPillsPerIntake(roundDose(request.getPillsPerIntake()));
        pill.setIntakeTimeArray(request.getIntakeTimes());
        pill.setUser(user);

        pillRepository.save(pill);
    }

    @Override
    @Transactional
    public void deletePillByUserIdAndMedicineName(Long userId, String medicineName) throws Exception {
        User user = userRepository.findById(userId)
                .orElseThrow(() -> new Exception("user not found"));

        long deletedCount = pillRepository.deleteByUserAndMedicineName(user, medicineName);
        if (deletedCount == 0) {
            throw new Exception("medicine not found");
        }
    }

    @Override
    @Transactional
    public List<PillDTO> getPillsByUserId(Long userId) {
        List<Pill> pills = pillRepository.findByUserUid(userId);
        return pills.stream().map(pill -> new PillDTO(
                pill.getId(),
                pill.getMedicineName(),
                pill.getDosageFrequency(),
                pill.getIntakeTimeArray(),
                pill.getMedicineCategory(),
                pill.getExpiryDate(),
                pill.getTotalPills(),
                pill.getPillsPerIntake()
        )).collect(Collectors.toList());
    }

    @Override
    @Transactional
    public TodayPillScheduleResponse getTodayPillSchedule(Long userId, LocalDate date) throws Exception {
        if (!userRepository.existsById(userId)) {
            throw new Exception("user not found");
        }

        LocalDate queryDate = date == null ? LocalDate.now() : date;
        List<Pill> pills = pillRepository.findByUserUid(userId);
        Map<String, String> storageCabinetMap = buildStorageCabinetMap();
        List<TodayPillScheduleItem> schedules = new ArrayList<>();

        for (Pill pill : pills) {
            String[] intakeTimes = pill.getIntakeTimeArray();
            for (String rawTime : intakeTimes) {
                LocalTime intakeTime = parseIntakeTime(rawTime);
                if (intakeTime == null) {
                    continue;
                }

                LocalDateTime scheduledTime = queryDate.atTime(intakeTime);
                boolean expired = pill.getExpiryDate() != null && pill.getExpiryDate().isBefore(queryDate);
                String medicineName = pill.getMedicineName();
                schedules.add(new TodayPillScheduleItem(
                        pill.getId(),
                        medicineName,
                        pill.getDosageFrequency(),
                        pill.getMedicineCategory(),
                        pill.getExpiryDate(),
                        expired,
                        intakeTime.format(OUTPUT_TIME_FORMATTER),
                        scheduledTime,
                        storageCabinetMap.getOrDefault(medicineName, "")
                ));
            }
        }

        schedules.sort(Comparator
                .comparing(TodayPillScheduleItem::getScheduledTime)
                .thenComparing(item -> item.getMedicineName() == null ? "" : item.getMedicineName()));
        return new TodayPillScheduleResponse(userId, queryDate, schedules.size(), schedules);
    }

    @Override
    @Transactional
    public void recordEatPill(Long userId, String medicineName, String storageCabinet) throws Exception {
        if (!userRepository.existsById(userId)) {
            throw new Exception("user not found");
        }

        User user = userRepository.getReferenceById(userId);
        Pill pill = pillRepository.findByUserAndMedicineName(user, medicineName);
        if (pill == null) {
            throw new Exception("medicine not found in user's pill list: " + medicineName);
        }

        EatPill eatPill = new EatPill();
        eatPill.setMedicineName(medicineName);
        eatPill.setIntakeTimes(pill.getIntakeTimes());
        eatPill.setStorageCabinet(normalizeCabinet(storageCabinet));
        eatPillRepository.save(eatPill);
    }

    @Override
    public List<Map<String, Object>> listEatPillRecords(Long userId) {
        return eatPillRepository.findAll().stream()
                .map(eatPill -> {
                    Map<String, Object> map = new HashMap<>();
                    map.put("id", eatPill.getId());
                    map.put("medicineName", eatPill.getMedicineName());
                    map.put("intakeTimes", eatPill.getIntakeTimes());
                    map.put("storageCabinet", eatPill.getStorageCabinet());
                    return map;
                })
                .collect(Collectors.toList());
    }

    @Override
    @Transactional
    public void deleteEatPillByMedicineName(Long userId, String medicineName) {
        eatPillRepository.deleteByMedicineName(medicineName);
    }

    @Override
    @Transactional
    public Map<String, Object> deductNearestDose(Long userId) throws Exception {
        if (!userRepository.existsById(userId)) {
            throw new Exception("user not found");
        }

        List<Pill> pills = pillRepository.findByUserUid(userId);
        if (pills.isEmpty()) {
            throw new Exception("pill list is empty");
        }

        LocalDateTime now = LocalDateTime.now(MEDICINE_TIME_ZONE);
        LocalDate today = now.toLocalDate();
        LocalDate yesterday = today.minusDays(1);
        LocalDateTime nearestScheduledTime = null;
        List<DoseCandidate> candidates = new ArrayList<>();

        for (Pill pill : pills) {
            DoseCandidate latestCandidate = findLatestCandidateBeforeNow(pill, today, yesterday, now);
            if (latestCandidate == null) {
                continue;
            }

            candidates.add(latestCandidate);
            if (nearestScheduledTime == null || latestCandidate.scheduledTime.isAfter(nearestScheduledTime)) {
                nearestScheduledTime = latestCandidate.scheduledTime;
            }
        }

        if (nearestScheduledTime == null) {
            throw new Exception("no valid intake time found");
        }

        List<Map<String, Object>> deductedItems = new ArrayList<>();
        for (DoseCandidate candidate : candidates) {
            if (!candidate.scheduledTime.equals(nearestScheduledTime)) {
                continue;
            }

            Pill pill = candidate.pill;
            Double totalPills = pill.getTotalPills();
            Double pillsPerIntake = pill.getPillsPerIntake();
            if (totalPills == null || pillsPerIntake == null || pillsPerIntake <= 0) {
                continue;
            }

            double beforeTotal = roundDose(totalPills);
            double dose = roundDose(pillsPerIntake);
            double afterTotal = roundDose(Math.max(0D, beforeTotal - dose));
            pill.setTotalPills(afterTotal);
            pillRepository.save(pill);

            Map<String, Object> item = new HashMap<>();
            item.put("pillId", pill.getId());
            item.put("medicineName", pill.getMedicineName());
            item.put("scheduledTime", candidate.scheduledTime);
            item.put("beforeTotalPills", beforeTotal);
            item.put("pillsPerIntake", dose);
            item.put("afterTotalPills", afterTotal);
            item.put("notEnoughStock", beforeTotal < dose);
            deductedItems.add(item);
        }

        if (deductedItems.isEmpty()) {
            throw new Exception("nearest dose has no valid stock fields");
        }

        Map<String, Object> result = new HashMap<>();
        result.put("userId", userId);
        result.put("currentTime", now);
        result.put("nearestScheduledTime", nearestScheduledTime);
        result.put("total", deductedItems.size());
        result.put("deductedItems", deductedItems);
        return result;
    }

    @Override
    @Transactional
    public Map<String, Object> deductCabinetDose(Long userId, String storageCabinet) throws Exception {
        if (!userRepository.existsById(userId)) {
            throw new Exception("user not found");
        }

        String normalizedCabinet = normalizeCabinet(storageCabinet);
        if (normalizedCabinet.isEmpty()) {
            throw new Exception("storageCabinet can not be empty");
        }

        List<EatPill> cabinetRecords = eatPillRepository.findByStorageCabinet(normalizedCabinet);
        if (cabinetRecords.isEmpty()) {
            throw new Exception("no medicine assigned to cabinet " + normalizedCabinet);
        }

        User user = userRepository.getReferenceById(userId);
        Set<String> medicineNames = new LinkedHashSet<>();
        for (EatPill record : cabinetRecords) {
            if (record.getMedicineName() != null && !record.getMedicineName().trim().isEmpty()) {
                medicineNames.add(record.getMedicineName().trim());
            }
        }

        LocalDateTime now = LocalDateTime.now(MEDICINE_TIME_ZONE);
        List<Map<String, Object>> deductedItems = new ArrayList<>();
        for (String medicineName : medicineNames) {
            Pill pill = pillRepository.findByUserAndMedicineName(user, medicineName);
            if (pill == null) {
                continue;
            }

            Map<String, Object> item = deductPillStock(pill, normalizedCabinet);
            if (item != null) {
                deductedItems.add(item);
            }
        }

        if (deductedItems.isEmpty()) {
            throw new Exception("cabinet has no valid stock fields");
        }

        Map<String, Object> result = new HashMap<>();
        result.put("userId", userId);
        result.put("storageCabinet", normalizedCabinet);
        result.put("deductedAt", now);
        result.put("total", deductedItems.size());
        result.put("deductedItems", deductedItems);
        return result;
    }

    @Override
    @Transactional
    public Map<String, Object> deductSelectedCabinetDose(Long userId, String storageCabinet, List<String> medicineNames) throws Exception {
        if (!userRepository.existsById(userId)) {
            throw new Exception("user not found");
        }

        String normalizedCabinet = normalizeCabinet(storageCabinet);
        if (normalizedCabinet.isEmpty()) {
            throw new Exception("storageCabinet can not be empty");
        }
        if (medicineNames == null || medicineNames.isEmpty()) {
            throw new Exception("medicineNames can not be empty");
        }

        List<EatPill> cabinetRecords = eatPillRepository.findByStorageCabinet(normalizedCabinet);
        if (cabinetRecords.isEmpty()) {
            throw new Exception("no medicine assigned to cabinet " + normalizedCabinet);
        }

        Set<String> assignedMedicineNames = new LinkedHashSet<>();
        for (EatPill record : cabinetRecords) {
            if (record.getMedicineName() != null && !record.getMedicineName().trim().isEmpty()) {
                assignedMedicineNames.add(record.getMedicineName().trim());
            }
        }

        Set<String> selectedMedicineNames = new LinkedHashSet<>();
        for (String medicineName : medicineNames) {
            if (medicineName == null || medicineName.trim().isEmpty()) {
                continue;
            }
            String normalizedName = medicineName.trim();
            if (assignedMedicineNames.contains(normalizedName)) {
                selectedMedicineNames.add(normalizedName);
            }
        }

        if (selectedMedicineNames.isEmpty()) {
            throw new Exception("selected medicines are not assigned to cabinet " + normalizedCabinet);
        }

        User user = userRepository.getReferenceById(userId);
        LocalDateTime now = LocalDateTime.now(MEDICINE_TIME_ZONE);
        List<Map<String, Object>> deductedItems = new ArrayList<>();
        for (String medicineName : selectedMedicineNames) {
            Pill pill = pillRepository.findByUserAndMedicineName(user, medicineName);
            if (pill == null) {
                continue;
            }

            Map<String, Object> item = deductPillStock(pill, normalizedCabinet);
            if (item != null) {
                deductedItems.add(item);
            }
        }

        if (deductedItems.isEmpty()) {
            throw new Exception("selected medicines have no valid stock fields");
        }

        Map<String, Object> result = new HashMap<>();
        result.put("userId", userId);
        result.put("storageCabinet", normalizedCabinet);
        result.put("deductedAt", now);
        result.put("total", deductedItems.size());
        result.put("deductedItems", deductedItems);
        return result;
    }

    private LocalTime parseIntakeTime(String rawTime) {
        if (rawTime == null) {
            return null;
        }
        String normalized = rawTime.trim().replace("\"", "");
        if (normalized.isEmpty()) {
            return null;
        }
        try {
            return LocalTime.parse(normalized, INPUT_TIME_FORMATTER);
        } catch (Exception ignored) {
            return null;
        }
    }

    private DoseCandidate findLatestCandidateBeforeNow(Pill pill, LocalDate today, LocalDate yesterday, LocalDateTime now) {
        DoseCandidate latestCandidate = null;
        for (String rawTime : pill.getIntakeTimeArray()) {
            LocalTime intakeTime = parseIntakeTime(rawTime);
            if (intakeTime == null) {
                continue;
            }

            LocalDateTime todayCandidateTime = today.atTime(intakeTime);
            if (!todayCandidateTime.isAfter(now)) {
                latestCandidate = chooseLaterCandidate(latestCandidate, new DoseCandidate(pill, todayCandidateTime));
            }

            LocalDateTime yesterdayCandidateTime = yesterday.atTime(intakeTime);
            latestCandidate = chooseLaterCandidate(latestCandidate, new DoseCandidate(pill, yesterdayCandidateTime));
        }
        return latestCandidate;
    }

    private DoseCandidate chooseLaterCandidate(DoseCandidate current, DoseCandidate next) {
        if (current == null || next.scheduledTime.isAfter(current.scheduledTime)) {
            return next;
        }
        return current;
    }

    private Map<String, String> buildStorageCabinetMap() {
        Map<String, String> map = new HashMap<>();
        for (EatPill eatPill : eatPillRepository.findAll()) {
            String medicineName = eatPill.getMedicineName();
            if (medicineName != null && !medicineName.trim().isEmpty() && !map.containsKey(medicineName)) {
                map.put(medicineName, eatPill.getStorageCabinet());
            }
        }
        return map;
    }

    private String normalizeCabinet(String storageCabinet) {
        return storageCabinet == null ? "" : storageCabinet.trim().toUpperCase();
    }

    private double roundDose(Double value) {
        if (value == null) {
            return 0D;
        }
        return BigDecimal.valueOf(value)
                .setScale(2, RoundingMode.HALF_UP)
                .doubleValue();
    }

    private Map<String, Object> deductPillStock(Pill pill, String storageCabinet) {
        Double totalPills = pill.getTotalPills();
        Double pillsPerIntake = pill.getPillsPerIntake();
        if (totalPills == null || pillsPerIntake == null || pillsPerIntake <= 0) {
            return null;
        }

        double beforeTotal = roundDose(totalPills);
        double dose = roundDose(pillsPerIntake);
        double afterTotal = roundDose(Math.max(0D, beforeTotal - dose));
        pill.setTotalPills(afterTotal);
        pillRepository.save(pill);

        Map<String, Object> item = new HashMap<>();
        item.put("pillId", pill.getId());
        item.put("medicineName", pill.getMedicineName());
        item.put("storageCabinet", storageCabinet);
        item.put("beforeTotalPills", beforeTotal);
        item.put("pillsPerIntake", dose);
        item.put("afterTotalPills", afterTotal);
        item.put("notEnoughStock", beforeTotal < dose);
        return item;
    }

    private static class DoseCandidate {
        private final Pill pill;
        private final LocalDateTime scheduledTime;

        private DoseCandidate(Pill pill, LocalDateTime scheduledTime) {
            this.pill = pill;
            this.scheduledTime = scheduledTime;
        }
    }
}
