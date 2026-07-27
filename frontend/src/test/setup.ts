import '@testing-library/jest-dom/vitest'
import { cleanup } from '@testing-library/react'
import { afterEach } from 'vitest'

// Testing Library only registers its own cleanup when Vitest globals are
// enabled, and they are not. Without this, each test's DOM accumulates and
// queries start matching elements rendered by earlier tests.
afterEach(cleanup)
