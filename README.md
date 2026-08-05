# aem-eds-ai-workflow-demo
AEM EDS demo with AI workflow

## Environments
- Preview: https://main--aem-eds-ai-workflow-demo--agenticDraft.aem.page/
- Live: https://main--aem-eds-ai-workflow-demo--agenticDraft.aem.live/

## Documentation

Before using this project, go through the documentation on https://www.aem.live/docs/ and more specifically:
1. [Developer Tutorial](https://www.aem.live/developer/tutorial)
2. [The Anatomy of a Project](https://www.aem.live/developer/anatomy-of-a-project)
3. [Web Performance](https://www.aem.live/developer/keeping-it-100)
4. [Markup, Sections, Blocks, and Auto Blocking](https://www.aem.live/developer/markup-sections-blocks)

## Installation

```sh
npm i
```

## Linting

```sh
npm run lint
```

## Local server

```sh
aem up --forward-browser-logs
```

## Local development

1. Install the [AEM CLI](https://github.com/adobe/helix-cli): `npm install -g @adobe/aem-cli`
2. Install Chrome extension AEM Sidekick: https://chromewebstore.google.com/detail/aem-sidekick/igkmdomcgoebiipaifhmpfjhbjccggml
3. Start AEM Proxy: `aem up` (opens your browser at `http://localhost:3000`)
4. Open this directory in your favorite IDE and start coding :)
