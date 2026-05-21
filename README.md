# Dev Box Customizations Catalog

This repository contains Microsoft Dev Box customization definitions for demo purposes. It includes custom catalog tasks, team image definitions (covering both public and private package sources), and example user customization files.

## Structure

```
├── tasks/                              # Custom catalog tasks
│   ├── choco/                          # Install a package via Chocolatey
│   ├── choco-source/                   # Register a Chocolatey feed (with optional Key Vault credentials)
│   ├── dev-drive/                      # Create a Dev Drive (ReFS) as a VHDX or by resizing C:
│   └── winget-source/                  # Register a private Winget REST source
│
├── team-customizations/                # Team image definitions
│   ├── platform-team/                  # Winget-based image (public sources)
│   ├── choco-team/                     # Chocolatey-based image (public community feed)
│   ├── choco-private-team/             # Chocolatey-based image using a private feed over a VNet
│   └── winget-private-team/            # Winget-based image using a private REST source via Azure Function
│
└── user-customizations/                # Example per-user customization files
    ├── frontend-developer.yaml
    └── data-engineer.yaml
```

## Custom Tasks

The `tasks/` folder contains custom catalog tasks that can be referenced from image definitions and user customizations by name (or as `~/<task-name>` when consumed from another catalog).

| Task | Purpose | Key inputs |
| --- | --- | --- |
| **choco** | Installs a Chocolatey package, bootstrapping Chocolatey if it isn't already present. | `package` (required), `version`, `ignoreChecksums` |
| **choco-source** | Registers a Chocolatey package source, optionally with credentials and the ability to disable the default community feed. | `name`, `source`, `user`, `password`, `priority`, `disableDefaultSource` |
| **dev-drive** | Provisions a [Dev Drive](https://learn.microsoft.com/windows/dev-drive/) (ReFS) either as a new dynamically expanding VHDX or by carving space out of C:. Adapted from [dstamand-msft/Devbox-Customizations](https://github.com/dstamand-msft/Devbox-Customizations). | `type` (`vhdx` or `resize`), `driveLetter`, `size` (MB) |
| **winget-source** | Registers a private Winget REST source. Auth secrets (for example, an Azure Function key) are embedded in the source URL because winget's `--header` flag only sets the Windows-Package-Manager protocol header. | `name`, `source`, `trustLevel`, `removeDefaultSources` |

Credentials for the `choco-source` and `winget-source` tasks can be resolved at customization time from Azure Key Vault using the `{{<KEY_VAULT_SECRET_URI>}}` placeholder syntax.

## Team Customizations

Each subfolder under `team-customizations/` contains an `imagedefinition.yaml` consumed as a Dev Center catalog image definition. Attach this repository as a catalog to your Dev Center, then select the desired image definition when creating a Dev Box pool.

- **platform-team** — Baseline Winget-based image. Installs Visual Studio Code, Git, Node.js LTS, Python 3, and Microsoft Teams; creates a Dev Drive via inline PowerShell; configures Git defaults; and clones the team repository.
- **choco-team** — Equivalent image that installs core tools (VS Code, Git, 7-Zip, Notepad++) using the custom `choco` task instead of Winget.
- **choco-private-team** — Chocolatey-based image that pulls packages from a private feed reachable only over a VNet. Uses `buildProperties.networkConnection` to attach the build VM to a Dev Center network connection, provisions a 100 GB Dev Drive via the `dev-drive` task, then registers the private feed with `choco-source` (credentials resolved from Key Vault) and disables the public community source.
- **winget-private-team** — Winget-based image that registers a private Winget REST source fronted by an Azure Function. The function key is embedded in the source URL and resolved from Key Vault. Also uses `buildProperties.networkConnection` for VNet access. Package install steps are currently commented out pending validation of system-level winget installs from the private feed.

> **Note:** The private-feed image definitions reference example Key Vault URIs, network connection names, and source URLs. Replace them with values that match your environment.

## User Customizations

The `user-customizations/` folder contains example YAML files that individual developers can upload when creating a Dev Box. These layer personal preferences on top of the team image:

- **frontend-developer.yaml** — Clones the Next.js repo and installs Firefox Developer Edition, Figma, Windows Terminal, and VS Code extensions for ESLint, Prettier, Tailwind CSS, and auto-rename-tag.
- **data-engineer.yaml** — Clones an Azure SQL sample repo and installs Azure Data Studio, Azure Storage Explorer, Windows Terminal, Python data science packages (pandas, numpy, matplotlib, jupyter), and VS Code extensions for Python, Jupyter, and Cosmos DB.

To use: download the YAML file you want, then upload it via the **Apply customizations** option when creating a new Dev Box in the developer portal.
