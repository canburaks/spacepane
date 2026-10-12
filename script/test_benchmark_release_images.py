#!/usr/bin/env python3
"""Portable adversarial checks for image measurement reports; never builds Swift."""
from copy import deepcopy
import math
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import benchmark_release_images as images

SOURCES = {
    'png40-rgba': [(8000, 5000)], 'jpeg40-rgb': [(8000, 5000)],
    'png16-pair': [(4000, 4000)] * 2,
    'png40-plus16-pair': [(8000, 5000)] + [(4000, 4000)] * 2,
    'refused100-rgba': [(10000, 10000)], 'tiny-avif': [(32, 24)],
    'cancel-replace': [(8000, 5000)] * 2 + [(4000, 4000)] * 2,
}
METRICS = ['baselinePhysicalFootprintBytes', 'baselineLifetimePeakPhysicalFootprintBytes',
           'physicalFootprintHoldingBitmapsBytes', 'physicalFootprintAfterReleaseBytes',
           'lifetimePeakPhysicalFootprintBytes', 'maximumSampledPhysicalFootprintBytes',
           'sampledIncrementalPeakBytes']


def report(scenario='png40-rgba', phase='cold', count=1):
    sizes = SOURCES[scenario]
    decoded = [] if scenario == 'refused100-rgba' else sizes[scenario == 'cancel-replace':]
    bitmaps = []
    for width, height in decoded:
        side = math.ceil(min(max(width, height), 4096, math.sqrt(8_000_000 * max(width, height) / min(width, height))))
        factor = min(1, side / max(width, height))
        w, h = math.ceil(width * factor), math.ceil(height * factor)
        bitmaps.append(dict(width=w, height=h, bitsPerComponent=8, bytesPerRow=w * 4, storageBytes=w * h * 4))
    sample = dict(durationNanoseconds=20_000_000, physicalSampleCount=12,
                  maximumActiveLeases=0 if scenario == 'refused100-rgba' else 1,
                  maximumWaitingDecodes=0, sourceWidths=[w for w, h in sizes],
                  sourceHeights=[h for w, h in sizes], sourceEncodedBytes=[1024] * len(sizes),
                  requestedDecodeSides=[max(16, math.ceil(min(max(w, h), 4096, math.sqrt(8_000_000 * max(w, h) / min(w, h))))) for w, h in sizes],
                  decodedBitmaps=bitmaps, refusedImageCount=int(scenario == 'refused100-rgba'), thermalState=0,
                  cancelledAfterAdmission=scenario == 'cancel-replace',
                  retiredTaskReturnedBitmap=False if scenario == 'cancel-replace' else None,
                  cancellationInsideNativeCallObserved=None)
    sample.update(dict.fromkeys(METRICS, 1000))
    sample.update(baselinePhysicalFootprintBytes=100, baselineLifetimePeakPhysicalFootprintBytes=100,
                  sampledIncrementalPeakBytes=900)
    return dict(schemaVersion=1, scenario=scenario, phase=phase,
                unmeasuredWarmupPerformed=phase == 'warm',
                warmupLifetimePeakPhysicalFootprintBytes=100 if phase == 'warm' else None,
                afterReleaseScope='Swift image/source references dropped; immediate footprint may retain allocator/framework memory',
                sampleIntervalMilliseconds=2, baselinePhysicalFootprintBytes=100,
                baselineLifetimePeakPhysicalFootprintBytes=100, samples=[deepcopy(sample) for _ in range(count)])


class ReportTests(unittest.TestCase):
    def assert_invalid(self, value, scenario='png40-rgba', phase='cold', count=1):
        with self.assertRaises(ValueError):
            images.validate_report(value, scenario, phase, count)

    def test_all_required_cases_have_cold_and_explicit_warmed_reports(self):
        self.assertEqual(set(images.SCENARIOS), set(SOURCES))
        for scenario in SOURCES:
            for phase, count in [('cold', 1), ('warm', 3)]:
                images.validate_report(report(scenario, phase, count), scenario, phase, count)

    def test_capacity_one_policy_rejects_two_simultaneous_native_leases(self):
        for scenario in SOURCES:
            for phase in ('cold', 'warm'):
                with self.subTest(scenario=scenario, phase=phase):
                    value = report(scenario, phase)
                    value['samples'][0]['maximumActiveLeases'] = 2
                    self.assert_invalid(value, scenario, phase)

    def test_every_footprint_metric_is_present_finite_and_integer(self):
        for key in METRICS:
            for invalid in ['missing', None, float('nan'), float('inf'), -1, True, 1.5]:
                with self.subTest(key=key, invalid=invalid):
                    value = report()
                    if invalid == 'missing':
                        del value['samples'][0][key]
                    else:
                        value['samples'][0][key] = invalid
                    self.assert_invalid(value)
        for key in ['baselinePhysicalFootprintBytes', 'baselineLifetimePeakPhysicalFootprintBytes']:
            value = report(); del value[key]; self.assert_invalid(value)

    def test_rejects_wrong_dimensions_decode_outcome_and_bitmap_accounting(self):
        mutations = [dict(sourceWidths=[7999]), dict(sourceEncodedBytes=[8 * 1_048_576 + 1]),
                     dict(requestedDecodeSides=[4096]), dict(decodedBitmaps=[]), dict(refusedImageCount=1),
                     dict(maximumActiveLeases=3), dict(durationNanoseconds=float('nan')),
                     dict(sampledIncrementalPeakBytes=901), dict(physicalSampleCount=2)]
        for mutation in mutations:
            value = report(); value['samples'][0].update(mutation); self.assert_invalid(value)
        value = report(); value['samples'][0]['decodedBitmaps'][0]['storageBytes'] += 1; self.assert_invalid(value)
        value = report('refused100-rgba'); value['samples'][0]['decodedBitmaps'] = report()['samples'][0]['decodedBitmaps']
        self.assert_invalid(value, 'refused100-rgba')

    def test_cancellation_is_causal_without_claiming_native_call_observation(self):
        for key, invalid in [('cancelledAfterAdmission', False), ('retiredTaskReturnedBitmap', None),
                             ('cancellationInsideNativeCallObserved', True)]:
            value = report('cancel-replace'); value['samples'][0][key] = invalid
            self.assert_invalid(value, 'cancel-replace')
        value = report('cancel-replace'); value['samples'][0]['retiredTaskReturnedBitmap'] = True
        images.validate_report(value, 'cancel-replace', 'cold', 1)

    def test_rejects_wrong_phase_warmup_interval_schema_and_unknown_scenario(self):
        for mutation in [dict(scenario='jpeg40-rgb'), dict(phase='warm'), dict(schemaVersion=True),
                         dict(sampleIntervalMilliseconds=3), dict(unmeasuredWarmupPerformed=True),
                         dict(warmupLifetimePeakPhysicalFootprintBytes=100), dict(samples={})]:
            value = report(); value.update(mutation); self.assert_invalid(value)
        value = report(phase='warm'); value['warmupLifetimePeakPhysicalFootprintBytes'] = None
        self.assert_invalid(value, phase='warm')
        self.assert_invalid(report(), scenario='invented')


if __name__ == '__main__':
    unittest.main()
