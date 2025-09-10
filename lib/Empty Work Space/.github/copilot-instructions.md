<!-- Use this file to provide workspace-specific custom instructions to Copilot. For more details, visit https://code.visualstudio.com/docs/copilot/copilot-customization#_use-a-githubcopilotinstructionsmd-file -->

# Tradesperson Business Manager Web App - Copilot Instructions

## Project Context
This is a Next.js TypeScript web application that provides a desktop-optimized interface for a tradesperson business management system. It integrates with a Flutter mobile app through Firebase Firestore for real-time data synchronization.

## Code Style & Patterns

### TypeScript
- Use strict TypeScript with proper type definitions
- Prefer interfaces over types for object shapes
- Use proper React.FC typing for components
- Define props interfaces for all components

### React Components
- Use functional components with hooks
- Prefer named exports over default exports
- Use 'use client' directive for client-side components
- Keep components focused and single-responsibility

### Firebase Integration
- All database operations should use the FirestoreService class
- Implement proper error handling for Firebase operations
- Use real-time listeners for data that needs live updates
- Ensure user authentication before database operations

### Data Models
- Follow the same data structure as the Flutter mobile app
- Use the types defined in src/types/index.ts
- Maintain consistency with mobile app's Firestore collections
- All user data should be scoped under users/{userId}/

### UI/UX Guidelines
- Desktop-first responsive design with Tailwind CSS
- Use consistent color scheme (primary, secondary, success, warning, danger)
- Implement loading states for async operations
- Show proper error messages and success feedback
- Use the component library in src/components/ui/

### Performance
- Implement proper loading states
- Use React.memo for expensive components
- Optimize Firestore queries with proper indexing
- Implement pagination for large data sets

## File Organization
- Components should be organized by feature (jobs, customers, estimates, etc.)
- Reusable UI components go in src/components/ui/
- Business logic should be in service classes (src/lib/)
- Type definitions in src/types/
- Firebase configuration in src/lib/firebase.ts

## Key Features to Implement
1. Real-time dashboard with business metrics
2. Job management with status tracking
3. Customer database with search and filtering
4. Estimate builder with PDF generation
5. Invoice management and tracking
6. Price book with markup calculations
7. Settings for business configuration

## Integration Notes
- Maintain data compatibility with Flutter mobile app
- Use the same Firestore security rules and collection structure
- Implement offline support where possible
- Ensure seamless sync between web and mobile platforms

## Security Considerations
- Always verify user authentication before operations
- Use Firestore security rules for data protection
- Sanitize user inputs
- Implement proper error handling without exposing sensitive data
