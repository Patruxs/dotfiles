# Selected Unsupported Features Fail Clearly

When a profile selects a feature, setup must either install it for the current platform or fail with a clear unsupported-feature message. Silent skips are avoided because they make successful setup output unreliable and can leave requested capabilities missing.
