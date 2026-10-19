import * as pulumi from "@pulumi/pulumi";
import * as neon from "@pulumi/neon";

const config = new pulumi.Config();
const regionId = config.get("regionId") ?? "aws-us-east-1";
const pgVersion = Number(config.get("pgVersion") ?? "17");
const projectName = config.get("projectName") ?? "flowline-waitlist";
const branchName = config.get("branchName") ?? "dev-flowline";
const databaseName = config.get("databaseName") ?? "flowline";
const roleName = config.get("roleName") ?? "flowline_app";
// Required: Neon org ID. Set via `pulumi config set --secret orgId <org-...>`
// (find with `neon orgs list -o json` after `neon login`).
const orgId = config.requireSecret("orgId");

// Top-level Neon project. The inline `branch` block seeds the primary
// branch (main) with a database + role; child branches inherit both, so the
// dev branch below reuses them (no separate Role/Database resources — Neon
// returns ROLE_ALREADY_EXISTS otherwise).
const project = new neon.Project("flowline", {
    name: projectName,
    regionId: regionId,
    pgVersion: pgVersion,
    orgId: orgId,
    branch: {
        name: "main",
        databaseName: databaseName,
        roleName: roleName,
    },
    storePassword: "yes",
    // Free-tier-safe PITR window (max 6h = 21600s). Raise on paid plans.
    historyRetentionSeconds: 21600,
});

// Isolated branch for the dev-flowline stack (parent defaults to primary).
const appBranch = new neon.Branch("dev", {
    projectId: project.id,
    name: branchName,
});

// Single read_write compute per branch.
const appEndpoint = new neon.Endpoint("dev-rw", {
    projectId: project.id,
    branchId: appBranch.id,
    type: "read_write",
    autoscalingLimitMinCu: 0.25,
    autoscalingLimitMaxCu: 1,
});

// Role + database are inherited from main (seeded via the Project's branch
// block), so read the dev branch's password via data source instead of
// creating duplicates.
const appPassword = neon.getBranchRolePasswordOutput({
    projectId: project.id,
    branchId: appBranch.id,
    roleName: roleName,
});

// Pooled-ready DATABASE_URL for the Next.js app (use as DATABASE_URL).
export const databaseUrl = pulumi.secret(
    pulumi.interpolate`postgresql://${roleName}:${appPassword.password}@${appEndpoint.host}/${databaseName}?sslmode=require`,
);
export const projectId = project.id;
export const defaultBranchId = project.defaultBranchId;
export const branchId = appBranch.id;
export const endpointHost = appEndpoint.host;
export const rolePassword = pulumi.secret(appPassword.password);
export const projectConnectionUri = pulumi.secret(project.connectionUri);
