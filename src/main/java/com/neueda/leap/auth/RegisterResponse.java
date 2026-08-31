package com.neueda.leap.auth;

import java.util.UUID;

public record RegisterResponse(
        UUID userId,
        String username,
        String email
) {
}
