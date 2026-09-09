import { ComponentFixture, TestBed } from '@angular/core/testing';
import { provideRouter } from '@angular/router';
import { LoginComponent } from './login.component';

describe('LoginComponent', () => {
  let fixture: ComponentFixture<LoginComponent>;
  let component: LoginComponent;

  beforeEach(async () => {
    await TestBed.configureTestingModule({
      imports: [LoginComponent],
      providers: [provideRouter([])],
    }).compileComponents();

    fixture = TestBed.createComponent(LoginComponent);
    component = fixture.componentInstance;
    fixture.detectChanges();
  });

  function el<T extends HTMLElement>(selector: string): T | null {
    return (fixture.nativeElement as HTMLElement).querySelector<T>(selector);
  }

  it('should create', () => {
    expect(component).toBeTruthy();
  });

  it('should render email and password inputs', () => {
    expect(el('#email')).toBeTruthy();
    expect(el('#password')).toBeTruthy();
  });

  it('should start with an invalid, untouched form and no visible errors', () => {
    expect((component as any).form.invalid).toBe(true);
    expect(el('p.text-destructive')).toBeNull();
  });

  it('should reveal validation errors only after a submit attempt', () => {
    expect(el('p.text-destructive')).toBeNull();

    el<HTMLButtonElement>('button[type="submit"]')?.click();
    fixture.detectChanges();

    expect(fixture.nativeElement.querySelectorAll('p.text-destructive').length).toBeGreaterThan(0);
  });

  it('should toggle password visibility when the eye icon is clicked', () => {
    const passwordInput = el<HTMLInputElement>('#password')!;
    expect(passwordInput.type).toBe('password');

    el<HTMLButtonElement>('button[aria-label="Show password"]')?.click();
    fixture.detectChanges();

    expect(passwordInput.type).toBe('text');
    expect(el('button[aria-label="Hide password"]')).toBeTruthy();
  });

  it('should submit valid credentials', () => {
    const logSpy = vi.spyOn(console, 'log').mockImplementation(() => {});

    (component as any).form.setValue({ email: 'jane@example.com', password: 'password123' });
    fixture.detectChanges();

    el<HTMLFormElement>('form')?.dispatchEvent(new Event('submit'));
    fixture.detectChanges();

    expect(logSpy).toHaveBeenCalledWith('Login submitted', {
      email: 'jane@example.com',
      password: 'password123',
    });

    logSpy.mockRestore();
  });
});
