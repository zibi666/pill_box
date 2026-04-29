package com.lm.login_test.repository;

import com.lm.login_test.domain.Pill;
import com.lm.login_test.domain.User;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;

@Repository
public interface PillRepository extends JpaRepository<Pill, Long> {

    List<Pill> findByUser(User user);

    List<Pill> findByUserUid(Long userId);

    List<Pill> findByUserUidAndMedicineNameIn(Long userId, List<String> medicineNames);

    void deleteByUser(User user);

    boolean existsByUserAndMedicineName(User user, String medicineName);

    long deleteByUserAndMedicineName(User user, String medicineName);

    Pill findByUserAndMedicineName(User user, String medicineName);
}
