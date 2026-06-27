# Posit / R / RStudio / Shiny — Licensing Assessment for Internal Dashboard Use

| Field | Value |
|-------|--------|
| **Document version** | 1.0 |
| **Date** | 2026-06-21 |
| **Prepared for** | Internal Confluence / legal & audit review |
| **Status** | Factual mapping of **official license texts** to our described use case — **not legal advice** |
| **Review required by** | Company legal counsel / open-source compliance |

---

## 1. Purpose

This document records our **current and planned** data-dashboard architecture and maps it to **primary, publicly posted** license and product terms from:

- The R Foundation (R language)
- Posit Software, PBC (formerly RStudio, PBC) — RStudio IDE, commercial products, Professional Drivers
- Component licenses referenced by those vendors (AGPL-3, GPL, MIT)

**Method:** Excerpts below are copied from official sources listed in Section 10. Retrieval date: **2026-06-21**. Legal/audit teams should verify that linked documents have not changed and should apply internal open-source policy (including any prohibition on AGPL software).

---

## 2. Described use case (factual deployment summary)

The following describes our environment as implemented and planned. This section is **operational fact**, not a license interpretation.

### 2.1 Current production pattern

| Element | Description |
|---------|-------------|
| **Consumers (colleagues)** | Access dashboards via **web browser only** (HTTP). No RStudio login required to view published dashboards. |
| **Developers** | **Two (2)** staff develop and maintain Shiny applications. |
| **Hosting** | Self-managed Linux server (VPS); **nginx** reverse proxy; **systemd** services running `shiny::runApp()` per dashboard. |
| **Hub** | Custom Shiny “hub” landing page routing to multiple dashboard paths. |
| **Posit Connect** | **Not** used in this architecture. |
| **Posit Workbench** | **Not** used in this architecture. |
| **RStudio Server (open source)** | Installed on the server primarily for **development** (documented as SSH-tunnel access, not the primary path for business viewers). |
| **Data sources (today)** | Public APIs, bundled CSVs, MaStR parquet via DuckDB, Bundesagentur für Arbeit APIs, etc. |
| **Data sources (planned)** | **Apache Hive** / Hadoop ecosystem tables for large-scale analytics; visualization via Shiny dashboards. |

### 2.2 Role separation

| Role | Count | Software interaction |
|------|-------|----------------------|
| Dashboard viewer | Many colleagues | Browser → nginx → Shiny app only |
| Application developer | 2 | R + Shiny development; RStudio IDE (desktop and/or server) for authoring |

---

## 3. Software inventory and governing license family

| Component | Role in our stack | License family (per official source) | Posit EULA applies? |
|-----------|-------------------|--------------------------------------|---------------------|
| **R** | Runtime on server and dev machines | GPL-2 \| GPL-3 ([R Licenses](https://www.r-project.org/Licenses/)) | No |
| **Shiny** (R package) | Interactive dashboards | MIT + LICENSE file ([CRAN shiny](https://cran.r-project.org/package=shiny)) | No |
| **RStudio Desktop / Server (Open Source Edition)** | Developer IDE | AGPL-3 unless commercial agreement ([RStudio `COPYING`](https://github.com/rstudio/rstudio/blob/main/COPYING)) | No (unless Desktop Pro / commercial build) |
| **RStudio Desktop Pro, Posit Workbench, Posit Connect, Shiny Server Pro** | *Not currently deployed* | Posit proprietary — [EULA](https://posit.co/about/eula/) + [Software License Descriptions](https://posit.co/about/software-license-descriptions/) | Yes (with Order Form) |
| **Posit Professional Drivers** | *Optional for Hive ODBC* | Bundled with paid Posit products only ([Pro Drivers docs](https://docs.posit.co/pro-drivers/)) | N/A without paid product |
| **Hive / Hadoop ODBC driver (vendor)** | Alternative Hive connectivity | Vendor-specific (Cloudera, etc.) — separate from Posit | Depends on vendor |

---

## 4. Official excerpts — open-source RStudio (AGPL-3)

**Source:** RStudio Open Source `COPYING` file,  
https://github.com/rstudio/rstudio/blob/main/COPYING  
(retrieved 2026-06-21)

### 4.1 Choice of license: commercial agreement vs AGPL

> Unless you have received this program directly from Posit Software pursuant to  
> the terms of a commercial license agreement with Posit Software, then RStudio is  
> licensed to you under the AGPLv3, the terms of which are included below.

### 4.2 AGPL purpose (network server context)

> The GNU Affero General Public License is a free, copyleft license for  
> software and other kinds of works, specifically designed to ensure  
> cooperation with the community in the case of network server software.
>
> …  
> It requires the operator of a network server to  
> provide the source code of the modified version running there to the  
> users of that server. Therefore, public use of a modified version, on  
> a publicly accessible server, gives the public access to the source  
> code of the modified version.

### 4.3 Basic permission to run (AGPL Section 2)

> All rights granted under this License are granted for the term of  
> copyright on the Program, and are irrevocable provided the stated  
> conditions are met. This License explicitly affirms your unlimited  
> permission to run the unmodified Program.

### 4.4 Remote network interaction — modified versions (AGPL Section 13)

> Notwithstanding any other provision of this License, if you modify the  
> Program, your modified version must prominently offer all users  
> interacting with it remotely through a computer network (if your version  
> supports such interaction) an opportunity to receive the Corresponding  
> Source of your version by providing access to the Corresponding Source  
> from a network server at no charge, through some standard or customary  
> means of facilitating copying of software.

**Note for legal review:** AGPL obligations attach to **the Program** (RStudio) when **modified** and offered for remote interaction. Our **Shiny application code** is separate from the RStudio IDE binary. Whether and how AGPL applies to a given deployment must be determined by counsel under our policies and the full AGPL text.

---

## 5. Official excerpts — R language

**Source:** R Licenses page,  
https://www.r-project.org/Licenses/  
(retrieved 2026-06-21)

> R as a package is licensed under `GPL-2 | GPL-3`. File `doc/COPYING` is the same as GPL-2.

**Source:** GPL-3 text (via CRAN mirror),  
https://cran.r-project.org/web/licenses/GPL-3  
(retrieved 2026-06-21)

> giving you legal permission to copy, distribute and/or modify it.

---

## 6. Official excerpts — Shiny (R package)

**Source:** CRAN package page,  
https://cran.r-project.org/package=shiny  
(retrieved 2026-06-21)

| Field | Value |
|-------|--------|
| License | **MIT** + file LICENSE |

**Source:** Shiny `LICENSE` file header,  
https://github.com/rstudio/shiny/blob/main/LICENSE  
(retrieved 2026-06-21)

> YEAR: 2012-2025  
> COPYRIGHT HOLDER: Posit Software, PBC

*(Full MIT license text is in that file; CRAN lists MIT + LICENSE.)*

---

## 7. Official excerpts — Posit product positioning (open source vs commercial)

### 7.1 RStudio Open Source Edition (product page)

**Source:** https://posit.co/products/open-source/rstudio/  
(retrieved 2026-06-21)

Open Source Edition features include:

> Access the RStudio IDE on your desktop  
> …  
> **AGPL v3 license**

RStudio Desktop Pro features include:

> **A commercial license for organizations that cannot use AGPL software**  
> …  
> **Posit Professional Drivers for database connectivity**  
> …  
> **$1204.00 per year**

Posit also states:

> RStudio will remain free. Using RStudio without AI will cost nothing.

### 7.2 RStudio IDE User Guide — commercial edition

**Source:** https://docs.posit.co/ide/user/  
(retrieved 2026-06-21)

> RStudio is available in open source and commercial editions and runs on the desktop (Windows 11, macOS 14+, and Linux) or in a browser connected to RStudio Server or Posit Workbench.

Regarding Posit Workbench (commercial):

> The main advantages of using Posit Workbench are:
>
> - Enhanced security and authentication, including Single Sign On (SSO).  
> - …  
> - **A commercial license to remove the restrictions of the AGPL license.**

---

## 8. Official excerpts — Posit End User License Agreement (EULA)

**Applies to:** Posit **proprietary** Software under an Order Form — **not** to open-source RStudio downloaded without a commercial license.

**Source:** https://posit.co/about/eula/  
Version date on page: **November 2, 2022** (retrieved 2026-06-21)

### 8.1 Definition of “Software”

> **"Software"** means the object code version of the proprietary Posit software program(s) set forth on an Order Form (or downloaded by you as part of a free trial pursuant to Section 2 below) and all Updates provided to you by Posit. **"Software" expressly excludes** Posit's Posit Cloud and shinyapps.io online services…

### 8.2 Definition of “Open Source Language(s)”

> **"Open Source Language(s)"** means open source programming languages and software environments for statistical computing and graphics made available in source code form for free by third parties, such as **"R"** or Python.

### 8.3 Open Source Languages — separate licensing

> You acknowledge and agree that the Software is intended for use with Open Source Languages, and, as such, interoperates with certain open source components… **Posit is not responsible for Open Source Languages** and does not assume any obligations or liability with respect to your or your Users' use of Open Source Languages.

### 8.4 License grant (paid Software only)

> Posit grants you a limited, worldwide, nonexclusive, royalty-free license (without right of sublicense) **during the Subscription Term** to install and use the Software…

### 8.5 Customer Applications and dashboard viewers (paid Software context)

From Section 3.4.1 Restrictions:

> …you and your Users may use the Software to **develop and deploy Customer Applications** to the extent enabled by the Software…
>
> To the extent users of your Customer Applications access and use your Customer Applications as enabled through use of the Software, such users shall be deemed **"Users"** for all purposes hereunder **except** that such Users shall be restricted to **viewing your directory of Customer Applications and to using and viewing the output of your Customer Applications**. Such Users may not be authorized to, and must not, **develop, publish, or modify** Customer Applications.

**Note for legal review:** This viewer/developer distinction is written for **Posit proprietary Software** (e.g. Connect). Our **current** stack serves Shiny via nginx/systemd **without** Posit Connect; this EULA section does not by itself govern open-source Shiny deployment, but it illustrates how Posit structures **viewer vs developer** rights in its commercial platform.

### 8.6 Third-party hosting (VPS)

From Section 3.3:

> The Software may be installed within a virtual (or otherwise emulated) hardware system so long as… such virtual machines are run on hardware you own, lease or otherwise control **(including for such purpose the hardware of a third party hosting provider that hosts the Software for your benefit, such as Amazon Web Services)**.

---

## 9. Official excerpts — Software License Descriptions (paid products)

**Source:** https://posit.co/about/software-license-descriptions/  
Version date on page: **January 27, 2025** (retrieved 2026-06-21)

### 9.1 Anonymous Users vs Named Users

> **Anonymous User(s):** means Users that do not have network or server credentials and who do not login and authenticate to use the Software.
>
> **Named User(s):** means a particular individual as the User who is given network or server credentials to access and use the Software and who must login and authenticate in order to use the Software. Named Users expressly exclude Anonymous Users.

### 9.2 Posit Professional Drivers (paid bundle)

> **Posit Professional Drivers:** Posit Professional Drivers enable you to connect Posit Workbench, Posit Connect, RStudio Desktop Pro, RStudio Server Pro or Shiny Server Pro with third party database products and services. **You may download and use Posit Professional Drivers at no additional charge with such Software.**

### 9.3 RStudio Desktop Pro — Named User licensing

> **RStudio Desktop Pro:** RStudio Desktop Pro is licensed for use by **one Named User** on up to five computer desktop devices. **You must pay a license fee for each Named User** that you wish to access and use the Software.

### 9.4 Posit Connect — Interactive vs anonymous access

> **Anonymous Users** are not permitted to upload data or content to Posit Connect, but are allowed to access and use Posit Connect and to access data and content that is not Server-Controlled Content.
>
> **Interactive Content** will always be **Server-Controlled** and may only be accessed by **Named Users**.

**Note:** If the organization later adopts **Posit Connect**, license entitlements for **anonymous dashboard viewers** vs **named developers** must be taken from the Connect tier purchased (Basic / Enhanced / Advanced) and the full Software License Descriptions document.

---

## 10. Official excerpts — Hive connectivity and Professional Drivers

### 10.1 Apache Hive — driver options (Posit Solutions)

**Source:** https://solutions.posit.co/connections/db/databases/hive/  
(retrieved 2026-06-21)

**Option A — Hadoop vendor driver:**

> **Hadoop vendor** - Download and install the driver made available by the Hadoop cluster provider (Cloudera, Hortonworks, etc.). To locate the driver please consult the vendor's website.

**Option B — Posit Professional Drivers:**

> **Posit Professional Drivers** - Workbench, RStudio Desktop Pro, Connect, or Shiny Server Pro users can download and use Posit Professional Drivers at no additional charge. These drivers include an ODBC connector for Apache Hive.

**Package stack (official):**

> The `odbc` package, in combination with a driver, provides `DBI` support and an ODBC connection.

### 10.2 Professional Drivers — restriction to paid Posit software

**Source:** https://docs.posit.co/pro-drivers/  
(retrieved 2026-06-21)

> Posit offers Posit Professional Drivers for many common data sources **at no additional cost to current paying customers**.
>
> **Use of the Posit professional drivers is only available with other Posit professional software and not available on a standalone basis or with other software.**
>
> Use Posit professional drivers with the following products:
>
> - Posit Team bundle  
> - RStudio Desktop Pro  
> - Posit Workbench  
> - Posit Connect

**Source:** https://docs.posit.co/pro-drivers/desktop/  
(retrieved 2026-06-21)

> These drivers require one of the following Posit Professional products installed:
>
> - RStudio Desktop Pro  
> - Posit Workbench  
> - Posit Connect
>
> Download and/or use of these products is governed under the terms of the **Posit End User License Agreement**.

### 10.3 Professional Drivers — product list includes Hive

**Source:** https://solutions.posit.co/connections/db/tooling/pro-drivers/  
(retrieved 2026-06-21)

Listed databases include:

> - Apache Hive  
> - Apache Impala  
> - …

And:

> If you are using Workbench, RStudio Desktop Pro, Connect, or Shiny Server Pro, you can download and use Posit Professional Drivers **at no additional charge in the same machine**.

---

## 11. Mapping our use case to license categories (for legal review)

This section **does not** state compliance conclusions. It lists **questions** counsel should resolve using the excerpts above and internal policy.

### 11.1 Colleagues who only view dashboards in a browser

| Fact | Relevant official material |
|------|----------------------------|
| Viewers use HTTP/browser only; no RStudio IDE | Shiny is MIT-licensed (CRAN). Viewing output of a Shiny app is not the same as “using RStudio” under AGPL. |
| No Posit Connect in architecture | Posit Connect Named User / Anonymous User rules (Section 9) apply **only if** Connect is purchased later. |
| **Question for legal** | Under company OSS policy, is serving internally developed Shiny apps via nginx/systemd acceptable without Posit subscriptions? |

### 11.2 Two developers using open-source RStudio

| Fact | Relevant official material |
|------|----------------------------|
| 2 developers edit Shiny/R code | RStudio Open Source: AGPL-3 (`COPYING`); permission to run **unmodified** Program (Section 4.3). |
| Multiple developers on OSS Desktop | Posit product page lists Open Source Edition as **“Free”** with **“AGPL v3 license”** — no per-user fee stated for OSS edition. |
| **Question for legal** | Does internal use of AGPL-licensed RStudio by 2 employees require commercial Desktop Pro solely due to headcount? *(Not stated in Posit public terms — AGPL and company policy govern.)* |
| **Question for legal** | Is AGPL acceptable under company open-source policy? If not, Posit offers Desktop Pro with **“A commercial license for organizations that cannot use AGPL software”** (product page, Section 7.1). |

### 11.3 Self-hosted production (nginx + systemd + Shiny)

| Fact | Relevant official material |
|------|----------------------------|
| Not using Posit Connect / Workbench | EULA Section 8.1: EULA “Software” is proprietary programs on Order Form — **excludes** our current OSS-only path unless we purchase. |
| VPS hosting | EULA 3.3 explicitly contemplates third-party hosting providers for **Posit Software**; analogous self-hosting of OSS stack is outside EULA but governed by OSS licenses. |
| **Question for legal** | AGPL Section 13 if **RStudio Server (OSS)** is modified and exposed on network — source-offer obligations for **modified RStudio**, not automatically for separate Shiny apps (counsel to confirm). |

### 11.4 Planned Hadoop / Hive connectivity

| Path | Official requirement (facts only) |
|------|-----------------------------------|
| **A. Vendor Hive ODBC/JDBC driver** + R `odbc` package | Documented as first option on Posit Hive solutions page (Section 10.1). **No Posit subscription cited** for vendor driver path. |
| **B. Posit Professional Drivers (Hive ODBC)** | Documented as **only** for Workbench, Desktop Pro, Connect, or Shiny Server Pro (Sections 10.2–10.3). **Requires paid Posit product** per official docs. |
| **Question for legal / procurement** | If IT mandates Posit-supported Hive drivers, budget **Named User** licenses (Desktop Pro and/or Workbench) per Software License Descriptions. |
| **Question for IT** | Hadoop vendor driver license terms (Cloudera/Databricks/etc.) are **separate** from Posit. |

---

## 12. When official Posit documentation indicates paid subscriptions

Based **only** on cited Posit pages (not on inference):

| Scenario | Official basis |
|----------|----------------|
| **RStudio Desktop Pro** per developer | “You must pay a license fee for each Named User” ([Software License Descriptions](https://posit.co/about/software-license-descriptions/)); listed price **$1204.00 per year** ([product page](https://posit.co/products/open-source/rstudio/)). |
| **Posit Workbench** | Named User + Server licensing ([Software License Descriptions](https://posit.co/about/software-license-descriptions/)). |
| **Posit Connect** | Named User licensing; Anonymous User rules vary by tier ([Software License Descriptions](https://posit.co/about/software-license-descriptions/)). |
| **Posit Professional Drivers (Hive)** | “only available with other Posit professional software” ([Pro Drivers docs](https://docs.posit.co/pro-drivers/)). |
| **Commercial license to avoid AGPL** | Stated benefit of Workbench / Desktop Pro ([IDE User Guide](https://docs.posit.co/ide/user/), [product page](https://posit.co/products/open-source/rstudio/)). |

**Not listed as requiring Posit payment in cited sources:**

- Using **R** (GPL) and **Shiny** (MIT) to build and host applications without Posit proprietary products.
- Using **vendor-supplied** Hive/Hadoop ODBC drivers with the R `odbc` package (Hive solutions page, Option A).
- **Browser-only dashboard consumers** (no Posit product login) on a **non-Connect** self-hosted stack.

---

## 13. Items outside Posit licensing (still required for audit)

| Topic | Notes |
|-------|--------|
| **Hadoop / Hive platform** | Cluster licensing is vendor-specific (not covered by this document). |
| **Third-party data APIs** | Terms of use per provider (e.g. BNetzA MaStR, Bundesagentur Statistik, Energy-Charts, Open-Meteo). |
| **CRAN / R package licenses** | Each dependency may have its own license (GPL, MIT, Apache, etc.). A full **bill of materials (SBOM)** is recommended for audit. |
| **Server / cloud** | IONOS VPS terms, security, data residency — separate from RStudio licensing. |

---

## 14. Recommended actions for legal & audit teams

1. **Confirm** company policy on **AGPL-3** software (RStudio Open Source Edition).
2. **Confirm** whether current architecture (Section 2) remains accurate after any production change.
3. **Decide Hive path:** vendor ODBC (Section 10.1 Option A) vs Posit Professional Drivers (requires paid Posit product, Section 10.2).
4. If purchasing Posit products, execute **Order Form** under [EULA](https://posit.co/about/eula/) and apply [Software License Descriptions](https://posit.co/about/software-license-descriptions/) for Named User counts (**2 developers** minimum if both need licensed IDE/server access).
5. **Document** dashboard viewers as non-RStudio users (browser-only) in internal architecture records.
6. **Re-verify** all URLs and version dates on this page before Confluence publication or audit submission.

---

## 15. Source bibliography (primary links)

| # | Document | URL | Version / date on page |
|---|----------|-----|-------------------------|
| 1 | RStudio `COPYING` (AGPL-3) | https://github.com/rstudio/rstudio/blob/main/COPYING | As in repository `main` |
| 2 | R Licenses | https://www.r-project.org/Licenses/ | — |
| 3 | GPL-3 (CRAN mirror) | https://cran.r-project.org/web/licenses/GPL-3 | — |
| 4 | Shiny (CRAN) | https://cran.r-project.org/package=shiny | — |
| 5 | Shiny `LICENSE` | https://github.com/rstudio/shiny/blob/main/LICENSE | 2012–2025 |
| 6 | RStudio Open Source product page | https://posit.co/products/open-source/rstudio/ | Pricing shown on page |
| 7 | RStudio IDE User Guide | https://docs.posit.co/ide/user/ | 2026.05.1 |
| 8 | Posit End User License Agreement | https://posit.co/about/eula/ | November 2, 2022 |
| 9 | Software License Descriptions | https://posit.co/about/software-license-descriptions/ | January 27, 2025 |
| 10 | Posit Professional Drivers | https://docs.posit.co/pro-drivers/ | — |
| 11 | Pro Drivers — desktop install | https://docs.posit.co/pro-drivers/desktop/ | — |
| 12 | Pro Drivers — solutions overview | https://solutions.posit.co/connections/db/tooling/pro-drivers/ | — |
| 13 | Apache Hive — Posit Solutions | https://solutions.posit.co/connections/db/databases/hive/ | — |

---

## 16. Disclaimer

This document was prepared to support internal review. It **quotes** publicly available license and product text and **maps** it to a described technical architecture. It does **not**:

- Provide legal advice or a formal legal opinion  
- Certify compliance with AGPL, GPL, MIT, or Posit EULA  
- Replace review by qualified counsel and open-source compliance processes  

**Final licensing decisions remain with the organization’s legal and procurement functions.**

---

*End of document*
