import { ComponentFixture, TestBed } from '@angular/core/testing';
import { provideRouter } from '@angular/router';
import { RegisterComponent } from './register.component';

describe('RegisterComponent', () => {
  let fixture: ComponentFixture<RegisterComponent>;
  let component: RegisterComponent;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  let componentAny: any;

  const validFormValue = {
    firstName: 'Jane',
    middleName: '',
    lastName: 'Doe',
    username: 'janedoe',
    email: 'jane@example.com',
    dateOfBirth: '1990-01-01',
    ssn: '123-45-6789',
    address: '123 Main St, Springfield',
    traderLevel: 'BEGINNER',
    availableFunds: 5000,
    password: 'Password1!',
    confirmPassword: 'Password1!',
  };

  beforeEach(async () => {
    await TestBed.configureTestingModule({
      imports: [RegisterComponent],
      providers: [provideRouter([])],
    }).compileComponents();

    fixture = TestBed.createComponent(RegisterComponent);
    component = fixture.componentInstance;
    componentAny = component;
    fixture.detectChanges();
  });

  function el<T extends HTMLElement>(selector: string): T | null {
    return (fixture.nativeElement as HTMLElement).querySelector<T>(selector);
  }

  function typeInto(id: string, value: string): void {
    const input = el<HTMLInputElement>(`#${id}`)!;
    input.value = value;
    input.dispatchEvent(new Event('input'));
    fixture.detectChanges();
  }

  it('should create', () => {
    expect(component).toBeTruthy();
  });

  it('should render the key registration fields', () => {
    expect(el('#firstName')).toBeTruthy();
    expect(el('#lastName')).toBeTruthy();
    expect(el('#username')).toBeTruthy();
    expect(el('#ssn')).toBeTruthy();
    expect(el('#address')).toBeTruthy();
    expect(el('#availableFunds')).toBeTruthy();
    expect(el('#password')).toBeTruthy();
    expect(el('#confirmPassword')).toBeTruthy();
  });

  it('should default trader level to BEGINNER and available funds to the minimum', () => {
    expect(componentAny.form.controls.traderLevel.value).toBe('BEGINNER');
    expect(componentAny.form.controls.availableFunds.value).toBe(componentAny.minimumAvailableFunds);
  });

  it('should auto-format the SSN with dashes as digits are typed', () => {
    typeInto('ssn', '123456789');
    expect(componentAny.form.controls.ssn.value).toBe('123-45-6789');
    expect(el<HTMLInputElement>('#ssn')?.value).toBe('123-45-6789');
  });

  it('should reject a malformed SSN', () => {
    componentAny.form.controls.ssn.setValue('123456789');
    expect(componentAny.form.controls.ssn.invalid).toBe(true);
  });

  it('should strip spaces and special characters from the username as typed', () => {
    typeInto('username', 'Jane Doe!123');
    expect(componentAny.form.controls.username.value).toBe('JaneDoe123');
  });

  it('should block e/+/- keystrokes in the available funds field', () => {
    const input = el<HTMLInputElement>('#availableFunds')!;

    const blockedEvent = new KeyboardEvent('keydown', { key: 'e', cancelable: true });
    input.dispatchEvent(blockedEvent);
    expect(blockedEvent.defaultPrevented).toBe(true);

    const allowedEvent = new KeyboardEvent('keydown', { key: '5', cancelable: true });
    input.dispatchEvent(allowedEvent);
    expect(allowedEvent.defaultPrevented).toBe(false);
  });

  it('should reject available funds below the minimum', () => {
    componentAny.form.controls.availableFunds.setValue(1000);
    expect(componentAny.form.controls.availableFunds.invalid).toBe(true);
  });

  it('should update the password requirement checklist as the user types', () => {
    const items = () => fixture.nativeElement.querySelectorAll('ul li');

    typeInto('password', 'short');
    fixture.detectChanges();
    expect(items()[0].classList.contains('text-muted-foreground')).toBe(true);

    typeInto('password', 'Password1!');
    fixture.detectChanges();
    expect(items()[0].classList.contains('text-[#33FF00]')).toBe(true);
    expect(items()[1].classList.contains('text-[#33FF00]')).toBe(true);
    expect(items()[2].classList.contains('text-[#33FF00]')).toBe(true);
  });

  it('should toggle password and confirm password visibility independently', () => {
    const passwordInput = el<HTMLInputElement>('#password')!;
    const confirmInput = el<HTMLInputElement>('#confirmPassword')!;

    // The password field's toggle button is the first "Show password" button in the DOM.
    el<HTMLButtonElement>('button[aria-label="Show password"]')?.click();
    fixture.detectChanges();

    expect(passwordInput.type).toBe('text');
    expect(confirmInput.type).toBe('password');
  });

  it('should show a mismatch error when passwords differ', () => {
    componentAny.form.controls.password.setValue('Password1!');
    componentAny.form.controls.confirmPassword.setValue('Different1!');
    componentAny.form.controls.confirmPassword.markAsTouched();
    fixture.detectChanges();

    expect(fixture.nativeElement.textContent).toContain('Passwords do not match.');
  });

  it('should show validation errors only after a submit attempt', () => {
    expect(el('p.text-destructive')).toBeNull();

    el<HTMLButtonElement>('button[type="submit"]')?.click();
    fixture.detectChanges();

    expect(fixture.nativeElement.querySelectorAll('p.text-destructive').length).toBeGreaterThan(0);
  });

  it('should submit a fully valid registration', () => {
    const logSpy = vi.spyOn(console, 'log').mockImplementation(() => {});

    componentAny.form.setValue(validFormValue);
    fixture.detectChanges();

    expect(componentAny.form.valid).toBe(true);

    el<HTMLFormElement>('form')?.dispatchEvent(new Event('submit'));
    fixture.detectChanges();

    expect(logSpy).toHaveBeenCalledWith('Registration submitted', validFormValue);

    logSpy.mockRestore();
  });
});
