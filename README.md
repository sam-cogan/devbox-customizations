# Dev Box Customizations Catalog

This repository contains Dev Box customization definitions for demo purposes.

## Structure

```
├── team-customizations/
│   └── platform-team/
│       └── imagedefinition.yaml    # Team image definition (applied to all dev boxes in a pool)
│
└── user-customizations/
    ├── frontend-developer.yaml     # Example user customization for frontend developers
    └── data-engineer.yaml          # Example user customization for data engineers
```

## Team Customizations

The `team-customizations/platform-team/` folder contains an `imagedefinition.yaml` that is used as a catalog image definition. When attached to a Dev Box pool, it automatically:

- Clones the team's repository
- Installs core development tools (Visual Studio Code, Git, Node.js LTS, Python 3)
- Installs collaboration tools (Microsoft Teams, Postman)
- Configures Git settings via PowerShell

To use: attach this repository as a catalog to your Dev Box project, then select the `platform-team` image definition when creating a pool.

## User Customizations

The `user-customizations/` folder contains example YAML files that individual developers can upload when creating a Dev Box. These layer personal preferences on top of the team image:

- **frontend-developer.yaml** — Adds Firefox, Figma, and Visual Studio Code extensions for frontend work
- **data-engineer.yaml** — Adds Azure Data Studio, Python data science packages, and Azure Storage Explorer

To use: download the YAML file you want, then upload it via the "Apply customizations" option when creating a new Dev Box in the developer portal.
