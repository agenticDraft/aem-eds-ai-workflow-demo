- id: "F1"
  class: needs-the-human
  severity: cosmetic
  file: "package.json"
  finding: "the project name still holds this platform's own template default, not this project's own name"
  diff: |
    -  "name": "@adobe/aem-boilerplate",
    +  "name": "<awaiting answer: what should package.json's name say?>",
  question: "what should package.json's name say?"
- id: "F2"
  class: needs-the-human
  severity: cosmetic
  file: "package.json"
  finding: "the project description still holds this platform's own template default, not this project's own description"
  diff: |
    -  "description": "Starter project for Adobe Helix",
    +  "description": "<awaiting answer: what should package.json's description say?>",
  question: "what should package.json's description say?"
- id: "F3"
  class: judgment
  severity: cosmetic
  file: "package.json"
  finding: "repository.url points at the upstream template repository, not this project's own git remote — demoted from mechanical because package.json has been edited since the boilerplate import (3 commits)"
  diff: |
    -    "url": "git+https://github.com/adobe/aem-boilerplate.git"
    +    "url": "git+https://github.com/agenticDraft/aem-eds-ai-workflow-demo.git"
  recommendation: "replace the stale upstream url with the project's own git remote, git+https://github.com/agenticDraft/aem-eds-ai-workflow-demo.git"
  default: "replace the stale upstream url with the project's own git remote, git+https://github.com/agenticDraft/aem-eds-ai-workflow-demo.git"
- id: "F4"
  class: judgment
  severity: cosmetic
  file: "blocks/cards/cards.css"
  finding: "a raw hex color is close to, but not exactly, an adopted token"
  diff: |
    -  border: 1px solid #dadada;
    +  border: 1px solid var(--dividers-divider-1);
  recommendation: "replace the raw hex with the nearest adopted token, Dividers/Divider 1 (#E9E9E9, max channel difference 15)"
  default: "replace the raw hex with the nearest adopted token, Dividers/Divider 1 (#E9E9E9, max channel difference 15)"
