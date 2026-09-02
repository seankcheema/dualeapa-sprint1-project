import { Component } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { CommonModule } from '@angular/common';
import { RouterLink } from '@angular/router';
import { HlmCardImports } from '@spartan-ng/helm/card';
import { HlmFieldImports } from '@spartan-ng/helm/field';
import { HlmInput } from '@spartan-ng/helm/input';
import { HlmButton } from '@spartan-ng/helm/button';
import { HlmNativeSelectImports } from '@spartan-ng/helm/native-select';

@Component({
  selector: 'app-register',
  standalone: true,
  imports: [
    FormsModule,
    CommonModule,
    RouterLink,
    HlmCardImports,
    HlmFieldImports,
    HlmInput,
    HlmButton,
    HlmNativeSelectImports,
  ],
  templateUrl: './register.component.html',
  styleUrl: './register.component.css'
})
export class RegisterComponent {
  // Personal Information
  firstName: string = '';
  middleName: string = '';
  lastName: string = '';
  email: string = '';
  ssn: string = '';
  dateOfBirth: string = '';

  // Account Information
  username: string = '';
  password: string = '';
  confirmPassword: string = '';
  traderLevel: string = 'BEGINNER';

  // Address
  addressLine1: string = '';
  addressLine2: string = '';
  city: string = '';
  state: string = '';
  postalCode: string = '';
  country: string = 'US';

  // Form State
  showPassword: boolean = false;
  showConfirmPassword: boolean = false;
  currentStep: number = 1;
  errors: { [key: string]: string } = {};
  successMessage: string = '';

  traderLevels = ['BEGINNER', 'INTERMEDIATE', 'ADVANCED'];
  states = ['AL', 'AK', 'AZ', 'AR', 'CA', 'CO', 'CT', 'DE', 'FL', 'GA', 'HI', 'ID', 'IL', 'IN', 'IA', 'KS', 'KY', 'LA', 'ME', 'MD', 'MA', 'MI', 'MN', 'MS', 'MO', 'MT', 'NE', 'NV', 'NH', 'NJ', 'NM', 'NY', 'NC', 'ND', 'OH', 'OK', 'OR', 'PA', 'RI', 'SC', 'SD', 'TN', 'TX', 'UT', 'VT', 'VA', 'WA', 'WV', 'WI', 'WY'];

  // Validation rules
  validateField(field: string, value: string): string | null {
    switch (field) {
      case 'firstName':
      case 'lastName':
        if (!value.trim()) return `${field === 'firstName' ? 'First' : 'Last'} name is required`;
        if (value.length < 2) return `${field === 'firstName' ? 'First' : 'Last'} name must be at least 2 characters`;
        if (!/^[a-zA-Z\s'-]+$/.test(value)) return 'Name contains invalid characters';
        return null;

      case 'email':
        if (!value.trim()) return 'Email is required';
        if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value)) return 'Invalid email format';
        return null;

      case 'username':
        if (!value.trim()) return 'Username is required';
        if (value.length < 3) return 'Username must be at least 3 characters';
        if (value.length > 20) return 'Username must be 20 characters or less';
        if (!/^[a-zA-Z0-9_-]+$/.test(value)) return 'Username can only contain letters, numbers, hyphens, and underscores';
        return null;

      case 'password':
        if (!value) return 'Password is required';
        if (value.length < 8) return 'Password must be at least 8 characters';
        if (!/[A-Z]/.test(value)) return 'Password must contain at least one uppercase letter';
        if (!/[a-z]/.test(value)) return 'Password must contain at least one lowercase letter';
        if (!/[0-9]/.test(value)) return 'Password must contain at least one number';
        if (!/[!@#$%^&*]/.test(value)) return 'Password must contain at least one special character (!@#$%^&*)';
        return null;

      case 'confirmPassword':
        if (!value) return 'Please confirm your password';
        if (value !== this.password) return 'Passwords do not match';
        return null;

      case 'ssn':
        if (!value.trim()) return 'SSN is required';
        const ssnClean = value.replace(/\D/g, '');
        if (ssnClean.length !== 9) return 'SSN must be 9 digits';
        if (/^0{3}|^666|^9\d{2}/.test(ssnClean)) return 'Invalid SSN';
        return null;

      case 'dateOfBirth':
        if (!value) return 'Date of birth is required';
        const age = this.calculateAge(new Date(value));
        if (age < 18) return 'You must be at least 18 years old';
        if (age > 120) return 'Please enter a valid date of birth';
        return null;

      case 'addressLine1':
        if (!value.trim()) return 'Address is required';
        if (value.length < 5) return 'Please enter a valid address';
        return null;

      case 'city':
        if (!value.trim()) return 'City is required';
        if (!/^[a-zA-Z\s'-]+$/.test(value)) return 'City contains invalid characters';
        return null;

      case 'state':
        if (!value) return 'State is required';
        return null;

      case 'postalCode':
        if (!value.trim()) return 'Postal code is required';
        if (!/^\d{5}(-\d{4})?$/.test(value.replace(/\s/g, ''))) return 'Invalid postal code format (use XXXXX or XXXXX-XXXX)';
        return null;

      default:
        return null;
    }
  }

  // Helper: Calculate age from birthdate
  calculateAge(birthDate: Date): number {
    const today = new Date();
    let age = today.getFullYear() - birthDate.getFullYear();
    const monthDiff = today.getMonth() - birthDate.getMonth();
    if (monthDiff < 0 || (monthDiff === 0 && today.getDate() < birthDate.getDate())) {
      age--;
    }
    return age;
  }

  // Standardize SSN format
  formatSSN(value: string): string {
    const cleaned = value.replace(/\D/g, '').slice(0, 9);
    if (cleaned.length <= 3) return cleaned;
    if (cleaned.length <= 5) return `${cleaned.slice(0, 3)}-${cleaned.slice(3)}`;
    return `${cleaned.slice(0, 3)}-${cleaned.slice(3, 5)}-${cleaned.slice(5)}`;
  }

  // Standardize postal code
  formatPostalCode(value: string): string {
    const cleaned = value.replace(/\D/g, '');
    if (cleaned.length <= 5) return cleaned;
    return `${cleaned.slice(0, 5)}-${cleaned.slice(5, 9)}`;
  }

  // Standardize names (capitalize properly)
  formatName(value: string): string {
    return value
      .trim()
      .split(/\s+/)
      .map(word => word.charAt(0).toUpperCase() + word.slice(1).toLowerCase())
      .join(' ');
  }

  // Handle SSN input
  onSSNInput(event: any): void {
    const formatted = this.formatSSN(event.target.value);
    this.ssn = formatted;
  }

  // Handle postal code input
  onPostalCodeInput(event: any): void {
    const formatted = this.formatPostalCode(event.target.value);
    this.postalCode = formatted;
  }

  // Validate step before moving forward
  validateStep(step: number): boolean {
    this.errors = {};

    if (step === 1) {
      const firstNameError = this.validateField('firstName', this.firstName);
      const lastNameError = this.validateField('lastName', this.lastName);
      const emailError = this.validateField('email', this.email);
      const dobError = this.validateField('dateOfBirth', this.dateOfBirth);
      const ssnError = this.validateField('ssn', this.ssn);

      if (firstNameError) this.errors['firstName'] = firstNameError;
      if (lastNameError) this.errors['lastName'] = lastNameError;
      if (emailError) this.errors['email'] = emailError;
      if (dobError) this.errors['dateOfBirth'] = dobError;
      if (ssnError) this.errors['ssn'] = ssnError;

      return Object.keys(this.errors).length === 0;
    }

    if (step === 2) {
      const usernameError = this.validateField('username', this.username);
      const passwordError = this.validateField('password', this.password);
      const confirmPasswordError = this.validateField('confirmPassword', this.confirmPassword);

      if (usernameError) this.errors['username'] = usernameError;
      if (passwordError) this.errors['password'] = passwordError;
      if (confirmPasswordError) this.errors['confirmPassword'] = confirmPasswordError;

      return Object.keys(this.errors).length === 0;
    }

    if (step === 3) {
      const addressError = this.validateField('addressLine1', this.addressLine1);
      const cityError = this.validateField('city', this.city);
      const stateError = this.validateField('state', this.state);
      const postalCodeError = this.validateField('postalCode', this.postalCode);

      if (addressError) this.errors['addressLine1'] = addressError;
      if (cityError) this.errors['city'] = cityError;
      if (stateError) this.errors['state'] = stateError;
      if (postalCodeError) this.errors['postalCode'] = postalCodeError;

      return Object.keys(this.errors).length === 0;
    }

    return false;
  }

  // Move to next step
  nextStep(): void {
    if (this.validateStep(this.currentStep)) {
      // Standardize data
      if (this.currentStep === 1) {
        this.firstName = this.formatName(this.firstName);
        this.lastName = this.formatName(this.lastName);
        this.middleName = this.middleName ? this.formatName(this.middleName) : '';
      }
      if (this.currentStep === 3) {
        this.city = this.formatName(this.city);
      }
      this.currentStep++;
    }
  }

  // Move to previous step
  prevStep(): void {
    if (this.currentStep > 1) {
      this.currentStep--;
      this.errors = {};
      this.successMessage = '';
    }
  }

  // Submit registration
  onSubmit(): void {
    if (this.validateStep(3)) {
      // Standardize data
      this.city = this.formatName(this.city);

      const registrationData = {
        firstName: this.firstName,
        middleName: this.middleName,
        lastName: this.lastName,
        email: this.email,
        username: this.username,
        password: this.password,
        ssn: this.ssn,
        dateOfBirth: this.dateOfBirth,
        traderLevel: this.traderLevel,
        address: {
          line1: this.addressLine1,
          line2: this.addressLine2,
          city: this.city,
          state: this.state,
          postalCode: this.postalCode,
          country: this.country
        }
      };

      console.log('Registration submitted:', registrationData);
      this.successMessage = 'Registration successful! Redirecting to login...';
      this.errors = {};
      
      // Reset form
      setTimeout(() => {
        this.resetForm();
        // Redirect to login (implement actual navigation)
      }, 2000);
    }
  }

  // Reset form
  resetForm(): void {
    this.firstName = '';
    this.middleName = '';
    this.lastName = '';
    this.email = '';
    this.username = '';
    this.password = '';
    this.confirmPassword = '';
    this.ssn = '';
    this.dateOfBirth = '';
    this.addressLine1 = '';
    this.addressLine2 = '';
    this.city = '';
    this.state = '';
    this.postalCode = '';
    this.traderLevel = 'BEGINNER';
    this.currentStep = 1;
    this.errors = {};
    this.successMessage = '';
    this.showPassword = false;
    this.showConfirmPassword = false;
  }
}
