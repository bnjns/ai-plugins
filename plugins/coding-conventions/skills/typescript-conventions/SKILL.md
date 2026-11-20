---
name: typescript-conventions
description: "TypeScript and Jest conventions. Use when writing, refactoring, or reviewing TypeScript; creating shared packages; or writing Jest tests and mocks. Covers type safety, imports, package boundaries, instantiated API clients, SDK singleton modules, and mock patterns. Framework idioms stay in their framework skills; logging is out of scope here. Read coding-conventions first."
license: MIT
---

# TypeScript conventions

Rules use **MUST** (never bypass) and **SHOULD** (deviate only with justification). A framework's dependency injection already satisfies "instantiated clients" for the services it provides; framework idioms belong in that framework's own skill.

Also read the nearest `AGENTS.md` (package, lambda, service, or app) for local gotchas not covered here.

## Type safety

### SHOULD: Avoid type assertions (`as`)

Prefer proper types, generics, type guards, and control-flow narrowing over forcing a type. The permitted assertion form is `as const` for literal narrowing.

```typescript
// Bad
const order = body as OrderDto;

// Good
if (!isOrderDto(body)) {
  throw new Error("invalid order");
}

const modes = ["draft", "published"] as const;
```

### SHOULD: Avoid non-null assertions (`!`)

Prefer explicit checks and narrowing. `!` is acceptable only when you have already established the value is defined — a guard, invariant, or early return/throw — but TypeScript cannot carry that narrowing to the use site.

```typescript
// Bad — substitutes for a check
const name = user!.name;

// Good — narrow first
if (user === undefined) {
  throw new Error("user required");
}
const name = user.name;

// OK — existence established; compiler lost narrowing (e.g. closure, callback)
if (user === undefined) {
  throw new Error("user required");
}
queueMicrotask(() => doSomething(user!.id));
```

## Imports

### SHOULD: Follow package path conventions

- `@<scope>/*` — workspace shared packages, using the scope the repo's workspace packages already declare in their `package.json` `name` (never invent one)
- `@/*` — package-internal imports when `tsconfig` defines `paths` (e.g. lambdas, apps)
- Relative paths — tests under `tests/` importing `../src/...` in packages without path aliases

Do not mix styles within a package; match what `tsconfig` already establishes.

### MUST: Consumers of `@<scope>/*` use `module: "nodenext"`

TypeScript only honours `package.json` `exports` with NodeNext resolution (`"module": "nodenext"` implies it). Do **not** add `@<scope>/*` `paths` in consumer tsconfigs — that pulls package source into the program, lifts `rootDir`, and nests emit. Keep `paths` for internal aliases only (e.g. `@/*`). Build depended packages before typechecking (e.g. `pnpm --filter "{pkg}^..." build`). Jest may still map `@<scope>/*` to package source for tests; that does not belong in `tsconfig.json`.

## Module design

### MUST: `index.ts` barrels are re-exports only

A barrel must only re-export from siblings. No implementation, helpers, or types defined in `index.ts`. Prefer one sibling module plus a thin barrel over inventing a third file just to satisfy this rule.

### MUST: No test-only exports from production code

Testability comes from mockable module seams, not `*ForTests()` helpers exported from `src/`.

```typescript
// Bad
export function clearEnvCacheForTests(): void {
  cache.clear();
}

// Good — mock the module seam in tests (jest.mock); pair with jest.resetModules in beforeEach when the module holds module-scoped state (see Jest conventions)
```

### SHOULD: Shared packages receive resolved config from callers

Shared packages take caller-supplied config — URLs, secrets, bucket names — at construction or call time. Do not read `process.env` or call `getEnv` from a package whose job is not loading configuration.

```typescript
// Good — caller resolves env (e.g. lambda config.ts)
const client = await createOidcClient({
  serverUrl: await getEnv("OIDC_SERVER_URL"),
  clientSecret: await getEnv("OIDC_CLIENT_SECRET"),
});

// Bad — inside a shared auth package
const secret = await getEnv("OIDC_CLIENT_SECRET");
```

A package whose whole purpose is loading configuration is the exception.

### MUST: API clients are instantiated — never free functions

Config and dependencies go in at construction; methods take only call-specific args. Use a class or a factory that returns an object with methods.

Shared cross-cutting behaviour (fetch, auth, retries, error shaping) belongs in one private helper on the instance or closure — not repeated per method, and not passed in on every call.

```typescript
// Bad — deps as parameters on every call
export async function getPrintDocument(
  logger: Logger,
  baseUrl: string,
  tokenProvider: TokenProvider,
  message: GeneratePdfPayload,
): Promise<RenderTarget[]> { ... }

// Good — class
export class PrintClient {
  constructor(
    private readonly baseUrl: string,
    private readonly oidcClient: OidcClient,
  ) {}
  async getPrintDocument(message: GeneratePdfPayload): Promise<RenderTarget[]> { ... }
}

// Good — factory object
export async function createOidcClient(config: OidcClientConfig): Promise<OidcClient> {
  return { getAccessToken, invalidateToken };
}
```

Throw plain `Error` with status and body text unless callers genuinely need to branch on a bespoke error type.

### SHOULD: Large clients group methods by domain; small ones stay flat

When a client covers many endpoints across distinct areas, expose domain namespaces — not a long flat list of prefixed methods. Do not group prematurely: a client with one or a few endpoints stays flat.

```typescript
// Good — large client
api.orders.getById(1n);
api.fulfilment.cancelJob(1n);

// Bad
api.getOrderById(1n);
api.cancelFulfilmentJob(1n);

// Good — small client
client.getPrintDocument(message);
```

### SHOULD: Lazy integration clients live in a dedicated module

Colocate lazy singleton accessors for external SDKs or services in one module per integration area. Do not bury them inside unrelated modules or split each SDK call into its own file.

```typescript
// Good
let s3Client: S3Client | undefined;

export function s3(): S3Client {
  s3Client ??= new S3Client({ ... });
  return s3Client;
}
```

### SHOULD: No thin wrapper modules

If a function only forwards to one external call with no added logic, call through from the orchestrator inline — a one-call wrapper is not a useful abstraction.

```typescript
// Good — orchestrator builds the command and sends (e.g. generate.ts)
await s3().send(new PutObjectCommand({ Bucket, Key, Body, ContentType }));

// Bad — dedicated module whose only job is that single send
```

### SHOULD: Async factories do setup up-front

Factories that need discovery, auth bootstrap, or other one-time setup should await it at construction and return a ready client — not defer setup to the first method call.

```typescript
// Good — e.g. createOidcClient: discovery in factory, not in getAccessToken
export async function createOidcClient(config: OidcClientConfig): Promise<OidcClient> {
  const discoveryConfig = await oidc.discovery(...);
  return { getAccessToken: () => fetchToken(discoveryConfig), invalidateToken };
}

// Bad — sync factory that lazily discovers on first token request
```

### MUST: Cache values, not promises

Store resolved results, not in-flight promises. Promise caches add complexity for concurrent dedupe that is rarely needed.

```typescript
// Good — e.g. env lookup Map, token { accessToken, expiresAt }
const cache = new Map<string, string>();
cache.set(key, resolvedValue);

// Bad
const cache = new Map<string, Promise<string>>();
```

### MUST: File name casing

Follow the repo's lint config or its existing files. Otherwise, use kebab-case for modules (`oidc-client.ts`), and PascalCase for UI component files in frameworks whose convention it is (e.g. `DropdownMenu.svelte`, `DropdownMenu.tsx`).

### SHOULD: Name modules by domain, not by function

A file holds the code for a domain area — name it after that area, not after one exported function or implementation detail. When the directory already names the domain, reuse that noun for the file (`carriers.ts` under `shipping/`) rather than inventing a synonym or verb (`resolve.ts`).

Do not introduce a second, near-duplicate name for the same concept in the same directory. `shipping/shipping-carrier.ts` beside `shipping/carriers.ts` conflates the directory, the sibling, and the new file and adds confusion — pick one noun and stick to it.

```text
# Good
print.ts
aws.ts
oidc-client.ts
shipping/carriers.ts

# Bad — named after a function or mechanism
to-print-files.ts
print-queue.ts
oidc-client-credentials.ts

# Bad — duplicate concept names in the same folder
shipping/carriers.ts
shipping/shipping-carrier.ts
```

### SHOULD: Public config APIs take structured input

Expose caller-friendly types at module boundaries; encode wire format, serialization, and protocol details inside the module. Do not push formatting or transport shape onto callers.

```typescript
// Good — e.g. OIDC client: caller passes a list, module joins for the request
type Config = { scopes?: string[] };
const scope = config.scopes?.join(" ");

// Bad — caller must know how the value is encoded on the wire
type Config = { scope?: string };
```

## Jest conventions

### MUST: Typed mocks — `jest.fn<Return, [Args]>()`

Declare typed mocks at the top of the file, before `jest.mock()` factories.

```typescript
const mockGetPrintDocument = jest.fn<
  Promise<RenderTarget[]>,
  [GeneratePdfPayload]
>();
```

### MUST: Import the module under test statically after mocks

Declare typed mocks, then `jest.mock()` factories, then a normal static `import` of the module under test. Do not dynamically re-import the module under test in `beforeEach` — no `await import(...)`, no `let fn: typeof import("...")` reassigned per test.

When the module holds module-scoped caches or singletons, call `jest.resetModules()` in `beforeEach` alongside mock cleanup. Mock seams plus `resetModules` is enough; re-importing is not.

```typescript
// Good
jest.mock("../src/clients", () => ({
  ssm: () => ({ send: mockSsmSend }),
}));

import { getEnv } from "../src/env";

beforeEach(() => {
  jest.clearAllMocks();
  jest.resetModules();
  process.env = { ...originalEnv };
});

// Bad — do not re-import the module under test
let getEnv: typeof import("../src/env").getEnv;
beforeEach(async () => {
  jest.resetModules();
  ({ getEnv } = await import("../src/env"));
});
```

### MUST: Mock internal seams, not vendor SDKs

Mock your own modules (`@/aws`, `../src/clients`) and assert on what your code passes through them. Vendor SDK types (command classes, clients) are not stable mock targets.

```typescript
// Good — mock the seam, assert on send input
jest.mock("@/aws", () => ({ s3: () => ({ send: mockS3Send }) }));
expect(mockS3Send).toHaveBeenCalledWith(
  expect.objectContaining({ input: { Bucket: "my-bucket", Key: "..." } }),
);

// Bad — SDK command instances are not value-comparable
expect(mockS3Send).toHaveBeenCalledWith(new PutObjectCommand({ ... }));
```

### MUST: Constructor mocks are plain classes

Use a plain class in the mock factory so `jest.resetAllMocks()` does not strip implementations from `jest.fn()` used as constructors.

```typescript
jest.mock("@/print", () => ({
  PrintClient: class {
    getPrintDocument = mockGetPrintDocument;
  },
}));
```

### SHOULD: Mock lifecycle — `clearAllMocks` vs `resetAllMocks` vs `resetModules`

- `clearAllMocks()` — clears call history; keeps implementations set via `mockReturnValue` / `mockImplementation`
- `resetAllMocks()` — clears history and removes those implementations; use when `beforeEach` re-primes mocks (especially after constructor/factory mocks)
- `resetModules()` — clears the module registry for module-scoped caches; call in `beforeEach` with a static import of the module under test (see above) — not with a dynamic re-import

Use `clearAllMocks` + `resetAllMocks` + re-prime when mocks lose their setup after reset. Use `clearAllMocks` + `resetModules` when isolating module-level caches.

```typescript
beforeEach(() => {
  jest.clearAllMocks();
  jest.resetAllMocks();
  mockS3.mockReturnValue({ send: mockS3Send });
  mockS3Send.mockResolvedValue({});
});
```

### SHOULD: Static typed fixtures; minimal casting

Prefer plain typed `const` fixtures. In tests, `as unknown as` is the only acceptable `as` form — and only for partial doubles that must satisfy a large interface you do not need fully (e.g. a stub `Browser`).

### SHOULD: One spec per module; no cross-suite duplication

Each module gets its own spec for its behaviour. Composition/orchestration specs assert wiring only — they do not re-test HTTP, rendering, or mapping logic that belongs elsewhere.

### MUST: Spec file names match the source module

Name the spec after the file under test, not the parent directory: `carriers.ts` → `carriers.spec.ts`, not `shipping.spec.ts`.
