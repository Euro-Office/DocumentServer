/* SPDX-FileCopyrightText: 2026 Euro-Office contributors
 * SPDX-License-Identifier: AGPL-3.0-only
 *
 * x2t-sandbox: apply two-layer landlock before exec'ing x2t or docbuilder.
 *
 * Layer 1 allows READ_FILE|READ_DIR on the whole filesystem.
 * Layer 2 allows READ_FILE|READ_DIR only on specific directories that x2t
 * needs, intentionally excluding /etc/<company>/documentserver/ at the file
 * level (only READ_DIR is granted there, so individual files cannot be
 * opened for reading).
 *
 * Because landlock enforces AND-across-layers semantics, local.json — which
 * has no READ_FILE grant in layer 2 — is unreadable by the exec'd process
 * even though layer 1 would allow it.
 *
 * Usage: x2t-sandbox <binary> [args...]
 *
 * Falls back to plain exec if landlock is unavailable (kernel < 5.13 or
 * CONFIG_SECURITY_LANDLOCK disabled) so the binary still runs.
 */

#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <linux/landlock.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/prctl.h>
#include <sys/syscall.h>
#include <unistd.h>

static inline int ll_create_ruleset(const struct landlock_ruleset_attr *a,
                                    size_t s, uint32_t f)
{
    return (int)syscall(SYS_landlock_create_ruleset, a, s, f);
}

static inline int ll_add_rule(int rfd, enum landlock_rule_type t,
                               const void *attr, uint32_t f)
{
    return (int)syscall(SYS_landlock_add_rule, rfd, t, attr, f);
}

static inline int ll_restrict_self(int rfd, uint32_t f)
{
    return (int)syscall(SYS_landlock_restrict_self, rfd, f);
}

#define FS_READ (LANDLOCK_ACCESS_FS_READ_FILE | LANDLOCK_ACCESS_FS_READ_DIR)

static void allow_path(int rfd, const char *path, uint64_t access)
{
    struct landlock_path_beneath_attr a = { .allowed_access = access };
    a.parent_fd = open(path, O_PATH | O_CLOEXEC);
    if (a.parent_fd < 0)
        return; /* skip missing paths silently */
    ll_add_rule(rfd, LANDLOCK_RULE_PATH_BENEATH, &a, 0);
    close(a.parent_fd);
}

static int make_ruleset(void)
{
    struct landlock_ruleset_attr attr = { .handled_access_fs = FS_READ };
    return ll_create_ruleset(&attr, sizeof(attr), 0);
}

/*
 * apply_layer1: allow reading everything — baseline permissive layer.
 * Returns 0 on success, -1 if landlock is unavailable (caller should exec
 * without sandboxing).
 */
static int apply_layer1(void)
{
    int rfd = make_ruleset();
    if (rfd < 0)
        return -1;
    allow_path(rfd, "/", FS_READ);
    if (prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0)) {
        perror("x2t-sandbox: prctl PR_SET_NO_NEW_PRIVS");
        close(rfd);
        return -1;
    }
    if (ll_restrict_self(rfd, 0)) {
        perror("x2t-sandbox: landlock_restrict_self layer1");
        close(rfd);
        return -1;
    }
    close(rfd);
    return 0;
}

/*
 * apply_layer2: allow reading only paths x2t actually needs.
 * /etc/<company>/documentserver/ is intentionally granted READ_DIR only,
 * blocking READ_FILE on local.json and other files in that directory.
 */
static void apply_layer2(const char *company)
{
    int rfd = make_ruleset();
    if (rfd < 0)
        return;

    /* shared libraries */
    allow_path(rfd, "/lib",          FS_READ);
    allow_path(rfd, "/lib64",        FS_READ);
    allow_path(rfd, "/usr/lib",      FS_READ);
    allow_path(rfd, "/usr/lib64",    FS_READ);
    allow_path(rfd, "/usr/share",    FS_READ);

    /* document server assets: fonts, sdkjs, server binaries */
    allow_path(rfd, "/var/www",      FS_READ);
    allow_path(rfd, "/var/lib",      FS_READ);

    /* temp and working dirs */
    allow_path(rfd, "/tmp",          FS_READ);

    /* kernel/runtime pseudo-fs */
    allow_path(rfd, "/proc",         FS_READ);
    allow_path(rfd, "/dev",          FS_READ);
    allow_path(rfd, "/sys",          FS_READ);

    /* /etc: specific files needed by glibc/libc at startup */
    allow_path(rfd, "/etc/ld.so.cache",   LANDLOCK_ACCESS_FS_READ_FILE);
    allow_path(rfd, "/etc/ld.so.conf",    LANDLOCK_ACCESS_FS_READ_FILE);
    allow_path(rfd, "/etc/ld.so.conf.d",  FS_READ);
    allow_path(rfd, "/etc/localtime",     LANDLOCK_ACCESS_FS_READ_FILE);
    allow_path(rfd, "/etc/nsswitch.conf", LANDLOCK_ACCESS_FS_READ_FILE);
    allow_path(rfd, "/etc/hosts",         LANDLOCK_ACCESS_FS_READ_FILE);
    allow_path(rfd, "/etc/resolv.conf",   LANDLOCK_ACCESS_FS_READ_FILE);

    /* /etc/<company>/documentserver/: traversal + C++ configs in core/
     * READ_FILE intentionally omitted at directory level — blocks local.json
     * and other JSON files that are only for Node.js (node-config). */
    char conf_dir[256];
    snprintf(conf_dir, sizeof(conf_dir),
             "/etc/%s/documentserver", company);
    allow_path(rfd, conf_dir, LANDLOCK_ACCESS_FS_READ_DIR);

    char core_dir[256];
    snprintf(core_dir, sizeof(core_dir),
             "/etc/%s/documentserver/core", company);
    allow_path(rfd, core_dir, FS_READ);

    if (ll_restrict_self(rfd, 0))
        perror("x2t-sandbox: landlock_restrict_self layer2");
    close(rfd);
}

int main(int argc, char *argv[])
{
    if (argc < 2) {
        fprintf(stderr, "usage: x2t-sandbox <binary> [args...]\n");
        return 1;
    }

    const char *company = getenv("COMPANY_NAME_LOW");
    if (!company || company[0] == '\0')
        company = "euro-office";

    if (apply_layer1() < 0) {
        /* landlock unavailable: exec without sandboxing */
        execv(argv[1], argv + 1);
        perror("x2t-sandbox: execv");
        return 1;
    }

    apply_layer2(company);

    execv(argv[1], argv + 1);
    perror("x2t-sandbox: execv");
    return 1;
}
