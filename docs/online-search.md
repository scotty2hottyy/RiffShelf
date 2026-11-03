# Online tab search

Discover uses a provider interface and search service, separate from Flutter presentation. Songsterr is the enabled provider. Its public search, metadata and structured-track endpoints are unofficial and can change or become unavailable; network errors and incompatible responses are reported to the user. Search results identify guitar and bass where Songsterr provides track metadata. Selecting a result retrieves the current revision and lets the user choose a matching track. Only actual downloaded notes can be saved; the existing SQLite library stores the tab for offline viewing.

Ultimate Guitar is not enabled: Tab-Star's adapter requires a separate proxy, and no running or verified service is assumed. The independent backend in `server/` provides a health endpoint and a versioned router for future provider APIs; it does not yet implement search or connect to Flutter.

The Songsterr adapter is adapted from the local Tab-Star project. Songsterr content and endpoint access remain subject to Songsterr's applicable terms and rights; this integration does not grant a license to redistribute tablature. Verify provider terms and content permissions before distribution or production use.
