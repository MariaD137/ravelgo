# RavelGo Platform TODO

Last updated: 2026-07-29

## Overview
This document tracks remaining work for the RavelGo ride-hailing platform across frontend, backend, infrastructure, and polish.

---

## 🚀 Backend Features

### Payment & Billing
- [ ] **PAY-03**: Driver payouts
  - Weekly payout calculations to driver bank accounts
  - Payout history and statements
  - Tax document handling
  - Stripe Connect integration for driver bank verification
  - Priority: High
  - Status: Not started

### Data & Reporting
- [ ] Analytics dashboard queries (trips, revenue, user metrics)
- [ ] Driver/rider export reports
- [ ] Audit logging for admin actions
- [ ] Priority: Medium
- [ ] Status: Not started

### Advanced Features
- [ ] Loyalty tier advancement logic (beyond models)
- [ ] Fraud detection scoring (AI integration)
- [ ] Referral link tracking and reward distribution
- [ ] In-app messaging (persistent conversation history)
- [ ] Priority: Medium-Low
- [ ] Status: Models exist, logic not implemented

---

## 📱 Frontend (Flutter)

### User App (Rider)
- [ ] Connect to real backend API (currently mock)
- [ ] Real-time trip tracking on map
- [ ] In-app calling via Twilio/similar
- [ ] Payment method management (add/remove cards)
- [ ] Ride history search/filter
- [ ] Push notifications
- [ ] Priority: High
- [ ] Status: Mock MVP complete, needs backend integration

### Driver App
- [ ] Connect to real backend API (currently mock)
- [ ] Real-time ride request notifications
- [ ] Automatic decline/accept logic
- [ ] Navigation to pickup/dropoff (Google Maps integration)
- [ ] In-app calling
- [ ] Document upload improvements (camera capture, compression)
- [ ] Payout dashboard with bank account linking
- [ ] Priority: High
- [ ] Status: Mock MVP complete, needs backend integration

### Admin App
- [ ] Connect to real backend API (currently mock)
- [ ] Real-time dashboard KPI updates
- [ ] Dispute resolution workflow
- [ ] Bulk driver/rider management actions
- [ ] Report generation and export
- [ ] Priority: Medium
- [ ] Status: Mock MVP complete, needs backend integration

---

## 🧪 Testing & Quality

### Backend Testing
- [ ] **QA-04**: End-to-end tests (API + DB + WebSocket)
  - Trip lifecycle (request → matching → in-progress → complete)
  - Payment flow with real Stripe mock
  - Real-time location updates and trip status
  - WebSocket connection drops and reconnects
  - Priority: High
  - Status: Not started

### Frontend Testing
- [ ] **QA-02**: Flutter analyze & unit tests
  - Run `flutter analyze` on all three apps
  - Widget tests for critical screens
  - Integration tests for navigation
  - Priority: Medium
  - Status: Blocked (no Flutter SDK in environment)

### Manual QA
- [ ] Smoke test all three apps with real backend
- [ ] Accessibility audit (WCAG compliance)
- [ ] Performance profiling (app launch time, memory)
- [ ] Priority: Medium
- [ ] Status: Not started

---

## 🛠️ Infrastructure & DevOps

### Database & Scaling
- [ ] **IN-05**: Custom domain setup
  - Route 53 DNS configuration
  - CloudFront distribution custom domain
  - App Runner custom domain
  - SSL certificate management
  - Priority: Medium
  - Status: Not started

- [ ] **IN-07**: Database auto-scaling
  - RDS read replicas for load distribution
  - Connection pooling (RDS Proxy)
  - Query performance monitoring
  - Priority: Low (post-MVP scale)
  - Status: Not started

- [ ] **IN-08**: Secrets rotation
  - Automatic Stripe key rotation
  - RDS password rotation
  - GitHub OIDC provider rotation
  - Priority: Low (annual maintenance)
  - Status: Not started

### Observability
- [ ] Application performance monitoring (APM)
  - Request latency tracking
  - Database query profiling
  - Error rate trends
- [ ] Log aggregation and search
  - CloudWatch Logs insights queries
  - Error debugging dashboards
- [ ] Priority: Medium
- [ ] Status: Basic CloudWatch alarms in place, needs depth

### CI/CD Hardening
- [ ] Security scanning in GitHub Actions
  - Dependency vulnerability checks (npm audit)
  - Code secrets scanning
  - SAST (static analysis security testing)
- [ ] Automated performance regression detection
- [ ] Staging environment promotion workflow
- [ ] Priority: Medium
- [ ] Status: Basic backend CI exists, needs expansion

---

## ✨ Polish & Optimization

### Backend
- [ ] **PL-01**: Request/response validation & error messages
  - Standardize error response format
  - Input validation on all endpoints
  - User-friendly error messages
  - Priority: High

- [ ] **PL-02**: API documentation
  - OpenAPI spec (Swagger) completion
  - Example requests/responses for all endpoints
  - API changelog/versioning strategy
  - Priority: High

- [ ] **PL-03**: Rate limiting refinement
  - Per-user rate limits (not just global)
  - Tiered limits (free vs. paid users)
  - Whitelist for admin APIs
  - Priority: Medium

- [ ] **PL-04**: Database optimization
  - Index audit and creation
  - Query performance profiling
  - Connection pool tuning
  - Priority: Medium

- [ ] **PL-05**: Logging & debugging
  - Structured JSON logging
  - Request ID tracing
  - Performance logging (slow queries, long responses)
  - Priority: Low-Medium

### Frontend
- [ ] App icon finalization (App Store branding)
- [ ] Splash screen polish
- [ ] Onboarding flow refinement
- [ ] Deep linking support
- [ ] Offline mode (cache recently viewed data)
- [ ] Priority: Low-Medium
- [ ] Status: Not started

### DevOps
- [ ] Blue-green deployments for zero-downtime updates
- [ ] Automated rollback on failed health checks
- [ ] Cost optimization audit (unused resources, instance right-sizing)
- [ ] Priority: Low-Medium
- [ ] Status: Not started

---

## 📊 Status Summary

| Category | Total | Complete | In Progress | Pending |
|----------|-------|----------|-------------|---------|
| Backend Features | 5 | 4 | 0 | 1 |
| Frontend (Apps) | 3 | 1 | 0 | 2 |
| Testing | 5 | 0 | 0 | 5 |
| Infrastructure | 8 | 2 | 0 | 6 |
| Polish | 14 | 0 | 0 | 14 |
| **TOTAL** | **35** | **7** | **0** | **28** |

---

## Priority Matrix

### Must-Have (Before Launch)
1. Backend API integration in all three apps
2. E2E tests for trip lifecycle
3. Real payment processing (Stripe)
4. Driver payout system (PAY-03)
5. API documentation (PL-02)
6. Request/response validation (PL-01)

### Should-Have (First Few Weeks Post-Launch)
1. Custom domain setup (IN-05)
2. Advanced monitoring (APM, log aggregation)
3. Security scanning in CI/CD
4. Performance optimization (PL-04, PL-05)
5. Mobile app polish (icons, deep linking)

### Nice-to-Have (Later Phases)
1. Database auto-scaling (IN-07)
2. Secrets rotation (IN-08)
3. Blue-green deployments
4. Offline mode
5. Advanced admin dashboards

---

## Next Steps

1. **Immediate** (this sprint):
   - Connect user_app to real backend
   - Implement E2E tests (QA-04)
   - Add driver payout logic (PAY-03)

2. **Next** (following sprint):
   - Connect driver_app and admin_app to backend
   - Complete API documentation (PL-02)
   - Add security scanning to CI/CD

3. **Future** (post-MVP):
   - Database scaling and optimization
   - Advanced monitoring and alerting
   - Mobile app polish and submission to stores
