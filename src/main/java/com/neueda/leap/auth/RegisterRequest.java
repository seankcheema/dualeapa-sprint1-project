package com.neueda.leap.auth;

import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Past;
import jakarta.validation.constraints.Size;

import java.time.LocalDate;

/**
 * Details submitted when registering a new account.
 *
 * @param username    desired username (3-50 characters)
 * @param email       account email address
 * @param password    desired password (8-100 characters)
 * @param ssn         social security number, used for identity verification
 * @param dateOfBirth date of birth, must be in the past
 */
public record RegisterRequest(
        @NotBlank @Size(min = 3, max = 50) String username,
        @NotBlank @Email @Size(max = 100) String email,
        @NotBlank @Size(min = 8, max = 100) String password,
        @NotBlank String ssn,
        @NotNull @Past LocalDate dateOfBirth
) {
}
