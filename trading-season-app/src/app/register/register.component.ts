import { ChangeDetectionStrategy, Component, computed, signal } from '@angular/core';
import { toSignal } from '@angular/core/rxjs-interop';
import {
  AbstractControl,
  FormBuilder,
  ReactiveFormsModule,
  ValidationErrors,
  ValidatorFn,
  Validators,
} from '@angular/forms';
import { RouterLink } from '@angular/router';
import { NgIcon, provideIcons } from '@ng-icons/core';
import {
  lucideCheck,
  lucideDollarSign,
  lucideEye,
  lucideEyeOff,
  lucideLock,
  lucideMail,
  lucideMapPin,
  lucideUser,
  lucideUserPlus,
  lucideX,
} from '@ng-icons/lucide';
import { HlmCardImports } from '@spartan-ng/helm/card';
import { HlmFieldImports } from '@spartan-ng/helm/field';
import { HlmInputImports } from '@spartan-ng/helm/input';
import { HlmButtonImports } from '@spartan-ng/helm/button';
import { HlmNativeSelectImports } from '@spartan-ng/helm/native-select';

const SPECIAL_CHARACTER_PATTERN = /[^A-Za-z0-9]/;
const NUMBER_PATTERN = /\d/;
const SSN_PATTERN = /^\d{3}-\d{2}-\d{4}$/;
const USERNAME_PATTERN = /^[A-Za-z0-9_]+$/;
const MINIMUM_AVAILABLE_FUNDS = 5000;

function passwordsMatchValidator(): ValidatorFn {
  return (control: AbstractControl): ValidationErrors | null => {
    const password = control.get('password')?.value;
    const confirmPassword = control.get('confirmPassword')?.value;
    return password === confirmPassword ? null : { passwordMismatch: true };
  };
}

@Component({
  selector: 'app-register',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [
    ReactiveFormsModule,
    RouterLink,
    NgIcon,
    ...HlmCardImports,
    ...HlmFieldImports,
    ...HlmInputImports,
    ...HlmButtonImports,
    ...HlmNativeSelectImports,
  ],
  providers: [
    provideIcons({
      lucideMail,
      lucideLock,
      lucideUser,
      lucideMapPin,
      lucideDollarSign,
      lucideEye,
      lucideEyeOff,
      lucideUserPlus,
      lucideCheck,
      lucideX,
    }),
  ],
  templateUrl: './register.component.html',
  styleUrl: './register.component.css',
})
export class RegisterComponent {
  protected readonly showPassword = signal(false);
  protected readonly showConfirmPassword = signal(false);
  protected readonly submitted = signal(false);

  protected readonly traderLevels = ['BEGINNER', 'INTERMEDIATE', 'ADVANCED'] as const;
  protected readonly minimumAvailableFunds = MINIMUM_AVAILABLE_FUNDS;

  private readonly _fb = new FormBuilder();

  protected readonly form = this._fb.nonNullable.group(
    {
      firstName: ['', [Validators.required]],
      middleName: [''],
      lastName: ['', [Validators.required]],
      username: ['', [Validators.required, Validators.minLength(3), Validators.pattern(USERNAME_PATTERN)]],
      email: ['', [Validators.required, Validators.email]],
      dateOfBirth: ['', [Validators.required]],
      ssn: ['', [Validators.required, Validators.pattern(SSN_PATTERN)]],
      address: ['', [Validators.required]],
      traderLevel: ['BEGINNER', [Validators.required]],
      availableFunds: [
        MINIMUM_AVAILABLE_FUNDS,
        [Validators.required, Validators.min(MINIMUM_AVAILABLE_FUNDS)],
      ],
      password: [
        '',
        [
          Validators.required,
          Validators.minLength(8),
          Validators.pattern(NUMBER_PATTERN),
          Validators.pattern(SPECIAL_CHARACTER_PATTERN),
        ],
      ],
      confirmPassword: ['', [Validators.required]],
    },
    { validators: passwordsMatchValidator() },
  );

  private readonly _passwordValue = toSignal(this.form.controls.password.valueChanges, {
    initialValue: '',
  });

  protected readonly hasMinLength = computed(() => this._passwordValue().length >= 8);
  protected readonly hasNumber = computed(() => NUMBER_PATTERN.test(this._passwordValue()));
  protected readonly hasSpecialCharacter = computed(() =>
    SPECIAL_CHARACTER_PATTERN.test(this._passwordValue()),
  );

  protected onSsnInput(event: Event): void {
    const digits = (event.target as HTMLInputElement).value.replace(/\D/g, '').slice(0, 9);
    const formatted = [digits.slice(0, 3), digits.slice(3, 5), digits.slice(5, 9)]
      .filter(Boolean)
      .join('-');
    this.form.controls.ssn.setValue(formatted);
  }

  protected onUsernameInput(event: Event): void {
    const input = event.target as HTMLInputElement;
    const filtered = input.value.replace(/[^A-Za-z0-9_]/g, '');
    this.form.controls.username.setValue(filtered);
  }

  protected onAvailableFundsKeydown(event: KeyboardEvent): void {
    if (['e', 'E', '+', '-'].includes(event.key)) {
      event.preventDefault();
    }
  }

  protected togglePasswordVisibility(): void {
    this.showPassword.update((value) => !value);
  }

  protected toggleConfirmPasswordVisibility(): void {
    this.showConfirmPassword.update((value) => !value);
  }

  protected onSubmit(): void {
    this.submitted.set(true);

    if (this.form.invalid) {
      this.form.markAllAsTouched();
      return;
    }

    // TODO: wire up to registration service once backend endpoint is available
    console.log('Registration submitted', this.form.getRawValue());
  }
}

