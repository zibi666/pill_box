package com.lm.login_test.repository;

import com.lm.login_test.domain.EatPill;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;

@Repository
public interface EatPillRepository extends JpaRepository<EatPill, Long> {
    List<EatPill> findByMedicineName(String medicineName);

    List<EatPill> findByStorageCabinet(String storageCabinet);

    void deleteByMedicineName(String medicineName);
}
