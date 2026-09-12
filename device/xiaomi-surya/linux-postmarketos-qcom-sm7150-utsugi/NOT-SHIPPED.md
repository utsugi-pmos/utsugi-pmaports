# Research patches deliberately absent from this series

`surya/kernel/` in the research repository holds 113 patches; this aport carries
a subset. The difference is not accidental, but until 2026-09-12 nothing said so,
and one patch went missing without anybody noticing:

**`0118-sm7150-interconnect-qup0-keepalive` was lost in the migration.** It is
half of the fix for the 2026-09-08 reboot loop, and the loop came back on
2026-09-12 because of it (tasks/023). It is here now as `0117`.

This file exists so the next one is caught. **A patch in the research series and
not here must appear below, with a reason.**

## How to check

    for p in surya/kernel/*.patch; do
        # take a sample of the lines the patch ADDS and look for them in this aport
        ...
    done

The script is in tasks/023. Run it after any migration or rebase.

## Deliberately not shipped

| research patch | why |
|---|---|
| `0005-q6afe-svc-set-param-v2` | audio bring-up experiment, superseded by 0035+ |
| `0006-diagnostic-sweep-of-the-lpass-clocks` | diagnostic sweep, not a fix |
| `0010-our-own-va-macro-variant-with-no-fixed-version` | superseded |
| `0011-the-va-macro-asks-for-the-npl-clock-too` | superseded |
| `0012-the-tx-macro-opens-the-bolero-clock-gate` | superseded |
| `0016-control-the-codec-over-the-rx-link` | superseded |
| `0025-the-microphones-are-analogue-not-digital` | superseded; Xiaomi does not touch CDC_AMIC_CTL (0028) |
| `0026-the-adc-back-on-port-1-with-a-valid-configuration` | superseded by the final port mapping |
| `0027-port-mapping-from-xiaomis-device-tree` | superseded by the final port mapping |
| `0083-the-csiphy-had-no-analogue-supply` | **wrong and would have caused a regression.** Built on grepping upstream `sm7150.dtsi` instead of the patched tree, where `sm7150-xiaomi-common.dtsi:484` already wires both rails; applying it would have removed the 0.88 V rail. See `docs/CAMERA-05-phy-hears-the-sensor.md` |
| `0106-the-fingerprint-by-bit-banging` | diagnostic; superseded by 0110 |
| `0107-probe-scm` | diagnostic |
