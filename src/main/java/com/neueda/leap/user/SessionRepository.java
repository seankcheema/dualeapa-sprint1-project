package com.neueda.leap.user;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.UUID;

public interface SessionRepository extends JpaRepository<UserSession, UUID> {
}
