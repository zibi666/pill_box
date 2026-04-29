package com.lm.login_test.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

@Entity
@Table(name = "eat_pill")
public class EatPill {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    private String medicineName;

    @Column(columnDefinition = "TEXT")
    private String intakeTimes;

    private String storageCabinet;

    public Long getId() {
        return id;
    }

    public void setId(Long id) {
        this.id = id;
    }

    public String getMedicineName() {
        return medicineName;
    }

    public void setMedicineName(String medicineName) {
        this.medicineName = medicineName;
    }

    public String getIntakeTimes() {
        return intakeTimes;
    }

    public void setIntakeTimes(String intakeTimes) {
        this.intakeTimes = intakeTimes;
    }

    public String getStorageCabinet() {
        return storageCabinet;
    }

    public void setStorageCabinet(String storageCabinet) {
        this.storageCabinet = storageCabinet;
    }
}
