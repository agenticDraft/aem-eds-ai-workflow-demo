- id: "F1"
  class: mechanical
  severity: cosmetic
  file: "package.json"
  finding: "repository.url points at the upstream template repository, not this project's own git remote"
  diff: |
    -    "url": "git+https://example.test/upstream/template.git"
    +    "url": "git+https://example.test/agenticDraft/aem-eds-ai-workflow-demo.git"
- id: "F2"
  class: mechanical
  severity: poisoning
  file: "AGENTS.project.md"
  finding: "the breakpoint claim in this house-style document contradicts what the code actually enforces"
  diff: |
    -    the breakpoint is 1024px
    +    the breakpoint is 900px
