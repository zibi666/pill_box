package com.lm.login_test.dto;

import java.util.List;

public class PillListResponse {
    private String code;
    private String msg;
    private List<PillItem> data;

    public String getCode() { return code; }
    public void setCode(String code) { this.code = code; }
    public String getMsg() { return msg; }
    public void setMsg(String msg) { this.msg = msg; }
    public List<PillItem> getData() { return data; }
    public void setData(List<PillItem> data) { this.data = data; }

    public static class PillItem {
        private String medicineName;
        private Integer dosageFrequency;
        private Object intakeTimes;
        private String medicineCategory;
        private Object expiryDate;
        private Double totalPills;
        private Double pillsPerIntake;

        public String getMedicineName() { return medicineName; }
        public void setMedicineName(String medicineName) { this.medicineName = medicineName; }
        public Integer getDosageFrequency() { return dosageFrequency; }
        public void setDosageFrequency(Integer dosageFrequency) { this.dosageFrequency = dosageFrequency; }
        public Object getIntakeTimes() { return intakeTimes; }
        public void setIntakeTimes(Object intakeTimes) { this.intakeTimes = intakeTimes; }
        public String getMedicineCategory() { return medicineCategory; }
        public void setMedicineCategory(String medicineCategory) { this.medicineCategory = medicineCategory; }
        public Object getExpiryDate() { return expiryDate; }
        public void setExpiryDate(Object expiryDate) { this.expiryDate = expiryDate; }
        public Double getTotalPills() { return totalPills; }
        public void setTotalPills(Double totalPills) { this.totalPills = totalPills; }
        public Double getPillsPerIntake() { return pillsPerIntake; }
        public void setPillsPerIntake(Double pillsPerIntake) { this.pillsPerIntake = pillsPerIntake; }
    }
}
