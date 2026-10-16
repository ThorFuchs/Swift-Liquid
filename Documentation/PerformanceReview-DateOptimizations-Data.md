# Date optimization study: complete aggregate review

All 222 comparisons from the [targeted investigation](PerformanceReview-DateOptimizations.md) are retained here. First is unchanged controlA; second is normalization only, matching only, or independently built unchanged controlB. Positive change means higher cost. Medians are of six run medians, in microseconds. Public CPU is whole-process accounting; common rows measure wall time only. All libraries are unaugmented.

M marks an absolute median change of at least 10%; S marks a six-run range of at least 10% on either side. MAD is relative median absolute deviation; range is `(maximum − minimum) / median`. Flags use unrounded observations, not displayed rounded values. Three block effects remain in order. These observations do not establish exclusive parser CPU, statistical confidence, universal speedup, zero overhead or historical regression clearance. All raw samples and six unrounded medians remain in the bound artifact.

Study SHA-256: `32e7257acc41964016960432675bcba2395a74aea87961b23e7f0f85fd0ab7e8`.

## normalization-common-ordinary

26 comparisons; 3 median and 20 spread flags. First = controlA; second = normalization.

| Record | First µs | Second µs | Change % | Blocks % | MAD % first/second | Range % first/second | Flags |
| --- | ---: | ---: | ---: | --- | --- | --- | --- |
| custom-filter/parse-and-render | 22.508 | 22.375 | -0.591 | -0.59/+8.03/-6.18 | 0.08/0.16 | 6.16/17.52 | S |
| custom-filter/parse-and-render-metrics | 23.062 | 22.964 | -0.428 | +0.51/+8.36/-5.98 | 0.57/0.43 | 6.62/19.28 | S |
| custom-filter/reused-template | 17.758 | 17.731 | -0.149 | +0.01/+10.95/-11.47 | 0.27/0.38 | 18.13/23.33 | S |
| custom-filter/reused-template-metrics | 18.254 | 18.287 | +0.177 | +0.63/+11.12/-0.82 | 0.23/0.31 | 2.55/24.73 | S |
| date/parse-and-render | 45.402 | 38.739 | -14.675 | -11.22/-9.51/-15.08 | 4.12/0.28 | 15.68/9.62 | M S |
| date/parse-and-render-metrics | 43.806 | 39.259 | -10.381 | -10.59/+4.29/-15.63 | 5.55/0.40 | 12.60/21.69 | M S |
| date/reused-template | 42.002 | 35.745 | -14.897 | -12.54/-1.82/-14.90 | 2.05/0.83 | 13.74/20.69 | M S |
| date/reused-template-metrics | 38.523 | 36.026 | -6.483 | -6.41/+3.99/-15.05 | 0.95/0.35 | 12.01/22.82 | S |
| filter-chain/parse-and-render | 20.523 | 20.331 | -0.935 | -1.42/-0.44/-1.74 | 0.45/0.27 | 2.31/1.26 | — |
| filter-chain/parse-and-render-metrics | 20.979 | 20.920 | -0.282 | +2.98/-1.07/+0.82 | 0.31/0.79 | 1.43/6.38 | — |
| filter-chain/reused-template | 19.706 | 20.162 | +2.314 | +4.15/+1.17/+6.62 | 0.56/1.56 | 6.42/4.49 | — |
| filter-chain/reused-template-metrics | 18.602 | 19.059 | +2.453 | +4.32/-2.02/+4.53 | 1.12/1.90 | 6.61/6.85 | — |
| inspection/inspect-reused-template | 6.304 | 6.129 | -2.783 | -2.74/+5.15/-2.94 | 0.25/0.48 | 1.28/15.75 | S |
| inspection/parse-and-inspect | 16.144 | 15.777 | -2.274 | -2.18/+8.95/-1.73 | 0.42/0.42 | 2.44/22.41 | S |
| interpolation/parse-and-render | 18.040 | 18.223 | +1.014 | +29.11/+1.33/-1.97 | 0.64/0.86 | 46.33/3.72 | S |
| interpolation/parse-and-render-metrics | 17.839 | 17.883 | +0.248 | -1.07/+1.10/+0.02 | 0.55/0.61 | 2.80/1.59 | — |
| interpolation/reused-template | 19.489 | 20.653 | +5.972 | +45.76/+10.74/+2.62 | 4.82/0.61 | 65.28/4.04 | S |
| interpolation/reused-template-metrics | 19.249 | 19.618 | +1.916 | +8.48/-7.86/+2.12 | 2.70/1.98 | 11.18/12.58 | S |
| loop/parse-and-render | 36.495 | 36.278 | -0.597 | +3.93/-0.59/-0.46 | 0.15/0.43 | 1.09/10.42 | S |
| loop/parse-and-render-metrics | 37.053 | 36.718 | -0.905 | +3.38/-4.26/-12.30 | 0.52/0.85 | 26.94/14.27 | S |
| loop/reused-template | 30.971 | 31.127 | +0.505 | +2.46/+2.49/+0.22 | 0.36/1.11 | 1.21/6.95 | — |
| loop/reused-template-metrics | 31.292 | 31.223 | -0.222 | +2.39/-5.41/-0.18 | 0.37/1.13 | 17.87/8.45 | S |
| partial/parse-and-render | 24.751 | 24.586 | -0.664 | -1.57/-1.53/-0.57 | 0.83/1.06 | 13.92/12.53 | S |
| partial/parse-and-render-metrics | 25.163 | 25.135 | -0.111 | -2.44/-4.04/-0.28 | 0.56/0.29 | 14.36/6.48 | S |
| partial/reused-template | 18.632 | 18.504 | -0.690 | -3.69/-3.81/-0.12 | 1.28/0.55 | 13.99/4.99 | S |
| partial/reused-template-metrics | 18.986 | 18.892 | -0.493 | -2.08/-3.78/+0.69 | 2.19/0.31 | 17.98/9.71 | S |

## normalization-public-actor

24 comparisons; 4 median and 10 spread flags. First = controlA; second = normalization.

| Record | First µs | Second µs | Change % | Blocks % | MAD % first/second | Range % first/second | Flags |
| --- | ---: | ---: | ---: | --- | --- | --- | --- |
| filter/reused-cpu | 19.840 | 19.440 | -2.016 | -4.33/-2.71/+0.77 | 4.03/3.37 | 13.51/7.41 | S |
| filter/reused-wall | 19.734 | 19.334 | -2.027 | -3.87/-2.62/+0.65 | 3.69/3.15 | 12.34/7.04 | S |
| filter/source-cpu | 20.330 | 20.435 | +0.516 | +0.49/+0.20/+0.49 | 0.79/1.22 | 1.82/2.94 | — |
| filter/source-wall | 20.329 | 20.426 | +0.478 | +0.48/+0.19/+0.48 | 0.77/1.22 | 1.82/2.84 | — |
| interpolation/reused-cpu | 20.185 | 20.225 | +0.198 | +4.83/+0.30/-17.65 | 2.23/2.65 | 5.75/39.01 | S |
| interpolation/reused-wall | 19.744 | 19.801 | +0.289 | +5.10/-0.13/-16.86 | 1.72/2.85 | 5.03/37.38 | S |
| interpolation/source-cpu | 19.670 | 19.305 | -1.856 | -1.71/-1.20/-3.11 | 0.84/0.67 | 5.85/5.44 | — |
| interpolation/source-wall | 19.631 | 19.274 | -1.816 | -1.67/-1.34/-2.51 | 0.86/1.07 | 5.83/5.78 | — |
| invalid/reused-cpu | 33.520 | 31.125 | -7.145 | -7.84/-5.49/-4.84 | 0.51/0.67 | 1.88/5.11 | — |
| invalid/reused-wall | 33.510 | 31.123 | -7.123 | -7.83/-5.49/-3.53 | 0.52/0.68 | 1.88/7.88 | — |
| invalid/source-cpu | 36.610 | 33.310 | -9.014 | -9.71/-5.85/-5.29 | 0.48/0.87 | 1.26/9.61 | — |
| invalid/source-wall | 36.599 | 33.310 | -8.987 | -9.71/-5.82/-4.38 | 0.46/0.82 | 1.27/9.86 | — |
| iso/reused-cpu | 38.180 | 35.880 | -6.024 | -2.17/-6.43/-5.86 | 0.45/0.32 | 1.89/6.41 | — |
| iso/reused-wall | 38.170 | 35.872 | -6.019 | -2.18/-6.43/-5.90 | 0.46/0.37 | 1.89/6.40 | — |
| iso/source-cpu | 41.430 | 39.335 | -5.057 | -4.36/-5.22/-5.75 | 0.33/1.03 | 1.91/3.33 | — |
| iso/source-wall | 41.426 | 39.328 | -5.065 | -4.38/-5.23/-5.76 | 0.34/1.04 | 1.88/3.33 | — |
| rfc/reused-cpu | 35.075 | 31.160 | -11.162 | -11.24/-9.98/-9.05 | 0.09/0.61 | 0.29/6.26 | M |
| rfc/reused-wall | 35.076 | 31.155 | -11.179 | -11.26/-9.99/-8.30 | 0.09/0.61 | 0.26/7.96 | M |
| rfc/source-cpu | 37.975 | 32.985 | -13.140 | -13.24/-11.60/-8.71 | 0.72/0.89 | 1.92/12.25 | M S |
| rfc/source-wall | 37.973 | 32.979 | -13.150 | -13.27/-11.63/-7.52 | 0.72/0.90 | 1.95/14.94 | M S |
| unicode/reused-cpu | 39.460 | 40.080 | +1.571 | +0.29/+5.40/+6.57 | 0.13/1.48 | 1.04/11.28 | S |
| unicode/reused-wall | 39.457 | 40.088 | +1.598 | +0.33/+5.41/+7.35 | 0.15/1.50 | 1.10/12.78 | S |
| unicode/source-cpu | 42.645 | 43.030 | +0.903 | +0.34/+5.00/+6.38 | 0.15/0.87 | 1.08/12.04 | S |
| unicode/source-wall | 42.643 | 43.024 | +0.892 | +0.32/+5.00/+7.20 | 0.16/0.86 | 1.06/13.63 | S |

## normalization-public-concurrent

24 comparisons; 8 median and 8 spread flags. First = controlA; second = normalization.

| Record | First µs | Second µs | Change % | Blocks % | MAD % first/second | Range % first/second | Flags |
| --- | ---: | ---: | ---: | --- | --- | --- | --- |
| filter/reused-cpu | 3.480 | 3.600 | +3.448 | +2.68/+4.74/+0.28 | 3.59/5.83 | 13.51/14.17 | S |
| filter/reused-wall | 3.479 | 3.598 | +3.407 | +2.46/+4.56/+0.21 | 3.54/6.02 | 13.45/14.28 | S |
| filter/source-cpu | 5.970 | 5.900 | -1.173 | -1.18/+0.42/+0.33 | 4.02/2.88 | 8.88/9.15 | — |
| filter/source-wall | 5.966 | 5.894 | -1.208 | -1.24/+0.58/+0.22 | 3.94/2.76 | 8.80/9.15 | — |
| interpolation/reused-cpu | 1.935 | 1.940 | +0.258 | +1.04/+0.52/-1.03 | 2.58/3.61 | 7.24/8.76 | — |
| interpolation/reused-wall | 1.932 | 1.932 | -0.021 | +1.25/+0.44/-1.10 | 2.43/3.80 | 7.29/8.45 | — |
| interpolation/source-cpu | 3.655 | 3.655 | +0.000 | +0.83/+0.00/+0.55 | 3.01/3.28 | 7.66/7.66 | — |
| interpolation/source-wall | 3.649 | 3.656 | +0.194 | +0.94/+0.17/+0.58 | 2.98/3.27 | 7.59/7.53 | — |
| invalid/reused-cpu | 17.110 | 15.210 | -11.105 | -10.79/-11.45/-10.71 | 0.18/0.49 | 1.17/1.91 | M |
| invalid/reused-wall | 17.109 | 15.214 | -11.079 | -10.75/-11.45/-10.69 | 0.14/0.48 | 1.18/1.94 | M |
| invalid/source-cpu | 19.430 | 17.410 | -10.396 | -10.50/-10.28/-10.09 | 0.18/0.26 | 0.98/1.32 | M |
| invalid/source-wall | 19.426 | 17.414 | -10.358 | -10.48/-10.28/-10.08 | 0.19/0.26 | 1.03/1.30 | M |
| iso/reused-cpu | 20.485 | 19.340 | -5.589 | +2.74/-5.92/-6.19 | 0.71/0.93 | 1.71/10.24 | S |
| iso/reused-wall | 20.472 | 19.334 | -5.555 | +2.68/-5.92/-6.16 | 0.71/0.91 | 1.70/10.17 | S |
| iso/source-cpu | 23.155 | 22.215 | -4.060 | +3.93/-5.44/-5.69 | 1.34/3.04 | 3.24/14.22 | S |
| iso/source-wall | 23.155 | 22.210 | -4.082 | +3.93/-5.48/-5.68 | 1.33/3.03 | 3.22/14.25 | S |
| rfc/reused-cpu | 17.585 | 13.940 | -20.728 | -17.80/-20.98/-20.36 | 0.71/0.43 | 1.93/9.18 | M |
| rfc/reused-wall | 17.585 | 13.938 | -20.743 | -17.79/-21.06/-20.39 | 0.67/0.44 | 1.95/9.19 | M |
| rfc/source-cpu | 20.110 | 16.295 | -18.971 | -15.58/-19.35/-19.10 | 0.47/0.55 | 2.73/10.13 | M S |
| rfc/source-wall | 20.104 | 16.293 | -18.957 | -15.60/-19.36/-19.10 | 0.45/0.56 | 2.73/10.16 | M S |
| unicode/reused-cpu | 22.005 | 22.130 | +0.568 | +5.17/+0.52/+0.11 | 0.18/0.43 | 0.64/9.81 | — |
| unicode/reused-wall | 22.006 | 22.126 | +0.543 | +5.12/+0.51/+0.14 | 0.21/0.41 | 0.69/9.73 | — |
| unicode/source-cpu | 24.590 | 24.615 | +0.102 | +4.26/-0.28/+0.37 | 0.22/0.30 | 1.14/9.59 | — |
| unicode/source-wall | 24.581 | 24.611 | +0.124 | +4.25/-0.28/+0.38 | 0.21/0.32 | 1.14/9.58 | — |

## matching-common-ordinary

26 comparisons; 0 median and 20 spread flags. First = controlA; second = matching.

| Record | First µs | Second µs | Change % | Blocks % | MAD % first/second | Range % first/second | Flags |
| --- | ---: | ---: | ---: | --- | --- | --- | --- |
| custom-filter/parse-and-render | 22.545 | 22.596 | +0.225 | -4.38/+3.91/+1.19 | 0.33/0.47 | 10.58/8.75 | S |
| custom-filter/parse-and-render-metrics | 23.218 | 22.924 | -1.267 | -5.59/+4.45/-1.95 | 1.40/0.38 | 11.94/12.63 | S |
| custom-filter/reused-template | 17.832 | 17.750 | -0.460 | -9.05/+9.18/+3.67 | 0.68/0.34 | 19.12/19.22 | S |
| custom-filter/reused-template-metrics | 18.328 | 18.287 | -0.225 | -0.64/+6.97/+1.46 | 1.11/1.41 | 8.10/21.84 | S |
| date/parse-and-render | 41.327 | 40.296 | -2.493 | +1.59/-3.46/-1.17 | 0.09/0.92 | 0.37/10.13 | S |
| date/parse-and-render-metrics | 41.434 | 41.473 | +0.095 | -8.32/+3.95/+4.63 | 0.18/0.44 | 18.39/11.17 | S |
| date/reused-template | 37.559 | 37.060 | -1.331 | -1.45/+5.79/+3.24 | 0.21/0.33 | 1.71/14.38 | S |
| date/reused-template-metrics | 38.216 | 37.640 | -1.508 | -9.71/+1.48/+3.22 | 0.11/0.81 | 17.08/10.80 | S |
| filter-chain/parse-and-render | 20.546 | 20.555 | +0.047 | +0.57/-2.93/+2.00 | 0.49/0.72 | 6.39/4.62 | — |
| filter-chain/parse-and-render-metrics | 20.865 | 20.858 | -0.032 | +2.94/-2.32/-4.15 | 0.43/0.12 | 9.21/5.71 | — |
| filter-chain/reused-template | 19.387 | 19.685 | +1.537 | -3.50/+1.31/-1.18 | 0.97/1.41 | 7.13/10.73 | S |
| filter-chain/reused-template-metrics | 18.853 | 18.752 | -0.536 | +4.99/+1.84/-6.30 | 2.94/3.01 | 13.45/14.03 | S |
| inspection/inspect-reused-template | 6.543 | 6.374 | -2.576 | -11.54/+3.26/-3.67 | 3.74/0.95 | 31.08/13.59 | S |
| inspection/parse-and-inspect | 16.634 | 16.115 | -3.117 | -10.69/+2.06/-1.68 | 4.16/1.18 | 23.99/16.37 | S |
| interpolation/parse-and-render | 18.135 | 18.471 | +1.856 | +2.32/-0.17/+3.44 | 1.64/1.66 | 5.56/5.03 | — |
| interpolation/parse-and-render-metrics | 17.852 | 17.798 | -0.303 | -3.48/-3.73/+3.37 | 0.11/0.77 | 8.24/14.81 | S |
| interpolation/reused-template | 20.013 | 20.659 | +3.227 | -10.30/+1.68/+2.85 | 3.03/0.69 | 11.80/40.09 | S |
| interpolation/reused-template-metrics | 19.947 | 18.637 | -6.567 | -14.86/-7.28/-2.78 | 3.60/5.13 | 13.34/44.89 | S |
| loop/parse-and-render | 36.601 | 36.478 | -0.335 | +4.37/-4.27/-5.38 | 0.77/0.45 | 11.21/9.32 | S |
| loop/parse-and-render-metrics | 36.553 | 36.634 | +0.220 | +4.77/-1.44/-6.82 | 0.34/0.40 | 16.24/9.68 | S |
| loop/reused-template | 30.928 | 31.000 | +0.234 | +3.43/-1.74/-6.98 | 0.33/0.63 | 15.35/5.74 | S |
| loop/reused-template-metrics | 31.168 | 31.315 | +0.472 | +2.75/+0.72/-11.14 | 0.14/0.62 | 24.11/5.35 | S |
| partial/parse-and-render | 24.612 | 24.635 | +0.094 | +2.10/+0.98/-6.86 | 0.09/0.33 | 16.14/4.63 | S |
| partial/parse-and-render-metrics | 24.974 | 25.171 | +0.791 | +4.25/+0.40/+0.30 | 0.08/0.71 | 0.99/6.70 | — |
| partial/reused-template | 18.564 | 18.536 | -0.148 | +5.09/-0.26/-1.08 | 0.27/0.26 | 2.29/8.83 | — |
| partial/reused-template-metrics | 18.804 | 18.646 | -0.835 | +6.82/-0.96/-1.02 | 0.47/0.31 | 1.79/8.85 | — |

## matching-public-actor

24 comparisons; 2 median and 18 spread flags. First = controlA; second = matching.

| Record | First µs | Second µs | Change % | Blocks % | MAD % first/second | Range % first/second | Flags |
| --- | ---: | ---: | ---: | --- | --- | --- | --- |
| filter/reused-cpu | 19.825 | 19.410 | -2.093 | -8.33/+3.94/-1.50 | 1.01/3.66 | 10.79/16.90 | S |
| filter/reused-wall | 19.769 | 19.371 | -2.013 | -8.25/+6.51/-1.49 | 0.73/4.82 | 7.23/16.60 | S |
| filter/source-cpu | 20.400 | 21.385 | +4.828 | +0.48/+8.71/+3.73 | 1.15/3.60 | 6.42/11.36 | S |
| filter/source-wall | 20.400 | 21.593 | +5.851 | +0.28/+10.68/+3.68 | 1.15/4.53 | 8.96/13.11 | S |
| interpolation/reused-cpu | 20.680 | 18.140 | -12.282 | -10.99/-19.80/-4.56 | 2.27/11.30 | 11.80/28.45 | M S |
| interpolation/reused-wall | 20.228 | 18.157 | -10.240 | -9.88/-17.22/-3.97 | 2.13/9.21 | 10.92/24.94 | M S |
| interpolation/source-cpu | 19.215 | 19.700 | +2.524 | -2.15/+10.51/+2.13 | 0.99/4.29 | 3.85/14.31 | S |
| interpolation/source-wall | 19.157 | 19.786 | +3.284 | -0.90/+13.24/+2.07 | 0.99/4.32 | 3.79/17.46 | S |
| invalid/reused-cpu | 33.355 | 33.565 | +0.630 | +1.68/+1.12/-1.27 | 0.55/3.96 | 9.32/13.79 | S |
| invalid/reused-wall | 33.356 | 33.573 | +0.651 | +2.38/+1.90/-1.29 | 0.55/4.00 | 9.28/15.28 | S |
| invalid/source-cpu | 36.655 | 37.635 | +2.674 | +2.15/+1.83/+0.79 | 0.45/5.17 | 8.59/13.68 | S |
| invalid/source-wall | 36.667 | 37.616 | +2.587 | +3.16/+2.41/+0.76 | 0.46/6.12 | 8.64/15.02 | S |
| iso/reused-cpu | 38.195 | 37.385 | -2.121 | -6.09/+12.32/-1.90 | 0.85/0.24 | 9.48/35.76 | S |
| iso/reused-wall | 38.182 | 37.382 | -2.096 | -6.06/+12.15/-1.88 | 0.84/0.24 | 9.48/35.37 | S |
| iso/source-cpu | 41.670 | 41.370 | -0.720 | -5.34/-0.88/-1.83 | 0.92/1.63 | 8.83/9.48 | — |
| iso/source-wall | 41.661 | 41.372 | -0.694 | -5.36/-0.91/-1.80 | 0.92/1.64 | 8.85/9.47 | — |
| rfc/reused-cpu | 35.220 | 34.625 | -1.689 | -5.67/-0.85/-1.49 | 0.58/0.27 | 8.86/8.98 | — |
| rfc/reused-wall | 35.213 | 34.626 | -1.666 | -5.66/-0.86/-1.48 | 0.57/0.27 | 8.84/8.97 | — |
| rfc/source-cpu | 38.245 | 37.580 | -1.739 | -5.32/+10.18/-2.04 | 0.59/0.48 | 9.44/21.77 | S |
| rfc/source-wall | 38.245 | 37.570 | -1.766 | -5.33/+9.43/-2.05 | 0.60/0.47 | 9.42/20.16 | S |
| unicode/reused-cpu | 39.525 | 42.220 | +6.818 | +5.70/+4.58/+2.67 | 0.34/5.79 | 11.08/13.36 | S |
| unicode/reused-wall | 39.515 | 42.207 | +6.813 | +6.59/+5.06/+2.67 | 0.32/7.03 | 11.06/15.04 | S |
| unicode/source-cpu | 42.785 | 42.190 | -1.391 | -4.92/-2.02/-1.45 | 0.23/0.64 | 9.33/9.10 | — |
| unicode/source-wall | 42.756 | 42.184 | -1.338 | -4.90/-1.97/-1.44 | 0.18/0.63 | 9.30/9.10 | — |

## matching-public-concurrent

24 comparisons; 2 median and 20 spread flags. First = controlA; second = matching.

| Record | First µs | Second µs | Change % | Blocks % | MAD % first/second | Range % first/second | Flags |
| --- | ---: | ---: | ---: | --- | --- | --- | --- |
| filter/reused-cpu | 3.630 | 3.710 | +2.204 | +3.30/-15.44/+1.41 | 3.72/8.89 | 60.33/20.22 | S |
| filter/reused-wall | 3.629 | 3.707 | +2.147 | +3.11/-15.61/+1.39 | 3.80/8.95 | 60.44/20.14 | S |
| filter/source-cpu | 6.080 | 6.140 | +0.987 | -0.58/+1.86/+1.77 | 3.45/4.80 | 10.86/13.36 | S |
| filter/source-wall | 6.075 | 6.134 | +0.967 | -0.58/+1.78/+1.83 | 3.47/4.77 | 10.89/13.41 | S |
| interpolation/reused-cpu | 1.985 | 1.975 | -0.504 | +0.00/+0.00/+2.61 | 3.27/4.56 | 15.62/16.20 | S |
| interpolation/reused-wall | 1.985 | 1.970 | -0.787 | -0.08/-0.03/+2.40 | 3.26/4.66 | 15.24/16.25 | S |
| interpolation/source-cpu | 3.675 | 3.740 | +1.769 | +0.00/+0.52/+1.38 | 3.95/3.48 | 13.33/12.03 | S |
| interpolation/source-wall | 3.674 | 3.737 | +1.707 | +0.01/+0.59/+1.33 | 3.87/3.40 | 13.17/12.16 | S |
| invalid/reused-cpu | 17.240 | 15.485 | -10.180 | -10.39/-7.45/-9.35 | 0.99/1.03 | 5.51/7.94 | M |
| invalid/reused-wall | 17.236 | 15.480 | -10.186 | -10.41/-7.56/-9.33 | 1.02/1.01 | 5.50/7.90 | M |
| invalid/source-cpu | 19.500 | 17.925 | -8.077 | -8.23/-5.76/-7.62 | 0.97/0.73 | 5.85/7.70 | — |
| invalid/source-wall | 19.498 | 17.922 | -8.086 | -8.24/-5.80/-7.59 | 0.96/0.68 | 5.83/7.58 | — |
| iso/reused-cpu | 21.145 | 19.970 | -5.557 | -3.67/-2.40/-12.40 | 3.05/0.78 | 21.52/15.52 | S |
| iso/reused-wall | 21.133 | 19.965 | -5.525 | -3.63/-2.40/-12.42 | 3.04/0.76 | 21.63/15.42 | S |
| iso/source-cpu | 24.035 | 22.930 | -4.597 | -3.36/-3.17/-11.47 | 3.60/2.86 | 20.18/14.09 | S |
| iso/source-wall | 24.025 | 22.918 | -4.607 | -3.38/-3.20/-11.49 | 3.58/2.84 | 20.20/14.01 | S |
| rfc/reused-cpu | 17.805 | 17.170 | -3.566 | -3.51/-2.02/-12.71 | 0.84/0.79 | 22.35/14.27 | S |
| rfc/reused-wall | 17.805 | 17.168 | -3.580 | -3.52/-2.01/-12.75 | 0.87/0.81 | 22.46/14.27 | S |
| rfc/source-cpu | 20.915 | 19.880 | -4.949 | -2.91/-2.01/-12.17 | 3.51/1.46 | 22.38/14.39 | S |
| rfc/source-wall | 20.908 | 19.872 | -4.956 | -2.89/-2.06/-12.12 | 3.54/1.40 | 22.34/14.25 | S |
| unicode/reused-cpu | 22.490 | 21.480 | -4.491 | -4.22/+1.76/-10.85 | 2.16/0.37 | 19.25/11.45 | S |
| unicode/reused-wall | 22.486 | 21.474 | -4.503 | -4.22/+1.76/-10.84 | 2.17/0.36 | 19.23/11.42 | S |
| unicode/source-cpu | 24.745 | 24.180 | -2.283 | -2.15/+1.22/-10.97 | 0.67/0.93 | 19.84/16.00 | S |
| unicode/source-wall | 24.735 | 24.176 | -2.260 | -2.14/+1.22/-10.98 | 0.65/0.94 | 19.86/15.98 | S |

## identical-common-ordinary

26 comparisons; 1 median and 13 spread flags. First = controlA; second = controlB.

| Record | First µs | Second µs | Change % | Blocks % | MAD % first/second | Range % first/second | Flags |
| --- | ---: | ---: | ---: | --- | --- | --- | --- |
| custom-filter/parse-and-render | 22.472 | 22.978 | +2.250 | +3.77/+1.88/+2.51 | 0.19/2.63 | 1.81/7.83 | — |
| custom-filter/parse-and-render-metrics | 23.046 | 23.712 | +2.888 | +4.21/+0.60/+2.97 | 0.18/3.26 | 3.67/8.54 | — |
| custom-filter/reused-template | 17.683 | 18.307 | +3.530 | +8.28/+1.24/+4.79 | 0.43/3.77 | 3.63/16.86 | S |
| custom-filter/reused-template-metrics | 18.214 | 18.985 | +4.234 | +6.95/+3.50/+4.56 | 0.35/3.81 | 2.19/13.69 | S |
| date/parse-and-render | 41.313 | 41.325 | +0.029 | +0.17/+2.17/-0.27 | 0.20/0.03 | 2.11/6.08 | — |
| date/parse-and-render-metrics | 41.359 | 43.114 | +4.243 | +7.65/+4.58/+3.65 | 0.22/4.46 | 1.55/15.89 | S |
| date/reused-template | 37.582 | 37.766 | +0.490 | +0.49/+4.76/+3.90 | 0.16/0.53 | 2.33/9.53 | — |
| date/reused-template-metrics | 38.169 | 39.425 | +3.291 | +7.29/+2.87/+4.67 | 0.21/3.07 | 1.15/13.36 | S |
| filter-chain/parse-and-render | 20.539 | 20.351 | -0.915 | -1.00/-4.99/-0.44 | 0.41/0.48 | 5.92/1.27 | — |
| filter-chain/parse-and-render-metrics | 20.962 | 20.761 | -0.959 | +3.43/-4.23/-0.76 | 1.06/0.29 | 4.72/7.75 | — |
| filter-chain/reused-template | 19.386 | 19.571 | +0.953 | -0.41/+8.85/-2.21 | 3.51/0.49 | 15.91/4.53 | S |
| filter-chain/reused-template-metrics | 18.830 | 18.537 | -1.556 | +4.17/+1.72/-4.40 | 2.02/2.50 | 9.68/9.53 | — |
| inspection/inspect-reused-template | 6.294 | 6.382 | +1.387 | +7.45/+4.29/+0.39 | 0.32/1.61 | 3.38/13.78 | S |
| inspection/parse-and-inspect | 16.166 | 15.842 | -2.001 | +4.57/+2.13/-2.21 | 0.55/0.55 | 2.83/12.64 | S |
| interpolation/parse-and-render | 18.603 | 18.399 | -1.095 | +8.81/-7.52/-10.26 | 9.76/1.79 | 34.30/5.84 | S |
| interpolation/parse-and-render-metrics | 18.539 | 17.773 | -4.132 | -0.90/-11.99/-11.60 | 3.61/0.44 | 23.90/1.28 | S |
| interpolation/reused-template | 17.619 | 20.746 | +17.750 | +19.36/+14.04/+16.36 | 7.58/0.26 | 21.86/0.94 | M S |
| interpolation/reused-template-metrics | 19.447 | 18.423 | -5.266 | -6.17/-3.83/+0.76 | 6.80/0.52 | 26.71/4.38 | S |
| loop/parse-and-render | 36.484 | 36.381 | -0.281 | +5.00/-0.42/-0.95 | 0.48/0.39 | 1.20/10.02 | S |
| loop/parse-and-render-metrics | 36.865 | 36.469 | -1.075 | +4.89/-2.84/-0.94 | 0.58/0.44 | 4.95/10.27 | S |
| loop/reused-template | 30.884 | 30.845 | -0.127 | +2.39/-0.21/-0.72 | 0.32/0.04 | 1.62/4.44 | — |
| loop/reused-template-metrics | 31.209 | 31.068 | -0.453 | +2.69/-1.03/-0.52 | 0.67/0.15 | 1.64/5.62 | — |
| partial/parse-and-render | 24.645 | 24.540 | -0.423 | +0.41/-0.86/-0.59 | 0.58/0.52 | 2.76/2.78 | — |
| partial/parse-and-render-metrics | 25.141 | 25.091 | -0.198 | +0.19/-1.35/+0.07 | 0.32/0.07 | 2.60/0.51 | — |
| partial/reused-template | 18.617 | 18.476 | -0.755 | -0.40/-1.45/-1.06 | 0.82/0.10 | 3.31/1.55 | — |
| partial/reused-template-metrics | 19.123 | 18.741 | -1.999 | -5.02/-2.15/+0.66 | 0.95/0.54 | 9.42/2.56 | — |

## identical-public-actor

24 comparisons; 0 median and 13 spread flags. First = controlA; second = controlB.

| Record | First µs | Second µs | Change % | Blocks % | MAD % first/second | Range % first/second | Flags |
| --- | ---: | ---: | ---: | --- | --- | --- | --- |
| filter/reused-cpu | 18.950 | 19.680 | +3.852 | +1.02/-0.23/+11.99 | 3.96/3.81 | 15.25/12.86 | S |
| filter/reused-wall | 18.889 | 19.760 | +4.610 | +0.75/-0.28/+11.23 | 3.88/2.98 | 13.26/11.17 | S |
| filter/source-cpu | 20.575 | 20.425 | -0.729 | -2.16/+0.67/-1.07 | 2.28/1.00 | 7.39/7.93 | — |
| filter/source-wall | 20.566 | 20.422 | -0.700 | -2.09/+0.68/-1.44 | 2.27/1.01 | 10.23/9.90 | S |
| interpolation/reused-cpu | 19.745 | 20.585 | +4.254 | +4.37/-0.99/+5.44 | 5.47/3.30 | 24.87/26.72 | S |
| interpolation/reused-wall | 19.518 | 20.200 | +3.497 | +2.92/-0.65/+5.18 | 4.79/2.43 | 22.24/23.34 | S |
| interpolation/source-cpu | 19.615 | 19.540 | -0.382 | +10.79/-1.75/-3.33 | 1.99/3.74 | 9.48/23.23 | S |
| interpolation/source-wall | 19.558 | 19.497 | -0.311 | +10.24/-1.72/-3.51 | 2.09/3.77 | 11.82/21.91 | S |
| invalid/reused-cpu | 33.335 | 33.335 | +0.000 | -1.37/-0.57/+6.81 | 0.85/0.87 | 9.45/14.61 | S |
| invalid/reused-wall | 33.331 | 33.333 | +0.007 | -1.37/-0.55/+7.73 | 0.86/0.89 | 9.42/16.45 | S |
| invalid/source-cpu | 36.605 | 36.720 | +0.314 | -4.00/+0.36/+6.76 | 0.46/0.72 | 10.52/15.22 | S |
| invalid/source-wall | 36.602 | 36.714 | +0.304 | -4.00/+0.36/+7.47 | 0.47/0.72 | 10.50/16.60 | S |
| iso/reused-cpu | 38.095 | 38.275 | +0.473 | +0.16/+0.00/+0.80 | 0.28/0.14 | 1.23/0.89 | — |
| iso/reused-wall | 38.085 | 38.270 | +0.486 | +0.16/-0.01/+0.81 | 0.27/0.14 | 1.23/0.89 | — |
| iso/source-cpu | 41.440 | 41.535 | +0.229 | +0.85/+0.36/+0.07 | 0.21/0.59 | 0.82/2.29 | — |
| iso/source-wall | 41.432 | 41.530 | +0.236 | +0.85/+0.38/+0.07 | 0.23/0.57 | 0.83/2.28 | — |
| rfc/reused-cpu | 35.145 | 35.065 | -0.228 | +0.07/-0.33/-0.21 | 0.14/0.10 | 0.54/0.94 | — |
| rfc/reused-wall | 35.142 | 35.056 | -0.244 | +0.09/-0.38/-0.22 | 0.17/0.09 | 0.68/0.96 | — |
| rfc/source-cpu | 37.915 | 38.020 | +0.277 | +0.30/+0.33/-0.13 | 0.59/0.64 | 1.85/1.58 | — |
| rfc/source-wall | 37.907 | 38.010 | +0.271 | +0.33/+0.32/-0.11 | 0.60/0.65 | 1.84/1.60 | — |
| unicode/reused-cpu | 39.460 | 39.665 | +0.520 | -3.47/+0.46/+0.38 | 0.58/0.39 | 10.26/1.66 | S |
| unicode/reused-wall | 39.465 | 39.652 | +0.474 | -3.46/+0.44/+0.38 | 0.61/0.40 | 10.27/1.63 | S |
| unicode/source-cpu | 42.750 | 42.805 | +0.129 | -0.17/+0.00/+0.01 | 0.28/0.18 | 1.64/0.56 | — |
| unicode/source-wall | 42.745 | 42.800 | +0.128 | -0.18/-0.01/+0.00 | 0.30/0.17 | 1.59/0.56 | — |

## identical-public-concurrent

24 comparisons; 0 median and 24 spread flags. First = controlA; second = controlB.

| Record | First µs | Second µs | Change % | Blocks % | MAD % first/second | Range % first/second | Flags |
| --- | ---: | ---: | ---: | --- | --- | --- | --- |
| filter/reused-cpu | 3.475 | 3.760 | +8.201 | +5.39/+14.53/-3.38 | 3.45/4.39 | 28.49/20.74 | S |
| filter/reused-wall | 3.470 | 3.758 | +8.316 | +5.20/+14.55/-3.43 | 3.27/4.33 | 28.42/20.52 | S |
| filter/source-cpu | 5.990 | 6.305 | +5.259 | +0.17/+16.88/-0.39 | 4.34/4.60 | 19.70/22.84 | S |
| filter/source-wall | 5.990 | 6.298 | +5.134 | +0.17/+17.08/-0.36 | 4.38/4.86 | 19.44/22.75 | S |
| interpolation/reused-cpu | 1.975 | 1.985 | +0.506 | -2.02/+7.75/-0.25 | 2.78/3.02 | 13.67/19.65 | S |
| interpolation/reused-wall | 1.976 | 1.984 | +0.400 | -2.14/+7.55/-0.21 | 2.75/3.22 | 13.48/19.83 | S |
| interpolation/source-cpu | 3.730 | 3.670 | -1.609 | -2.01/+9.04/-5.95 | 3.22/3.95 | 17.96/24.80 | S |
| interpolation/source-wall | 3.724 | 3.673 | -1.382 | -1.98/+9.28/-5.80 | 3.31/3.95 | 18.18/24.99 | S |
| invalid/reused-cpu | 17.275 | 17.180 | -0.550 | -2.88/+7.23/-0.55 | 0.46/1.34 | 6.83/15.13 | S |
| invalid/reused-wall | 17.267 | 17.180 | -0.508 | -2.88/+7.18/-0.51 | 0.46/1.37 | 6.86/15.08 | S |
| invalid/source-cpu | 19.485 | 19.515 | +0.154 | +2.69/+6.68/-0.26 | 0.21/1.02 | 1.08/14.86 | S |
| invalid/source-wall | 19.475 | 19.508 | +0.167 | +2.73/+6.69/-0.25 | 0.20/1.03 | 1.11/14.90 | S |
| iso/reused-cpu | 20.655 | 20.620 | -0.169 | -7.27/+7.84/-5.16 | 0.94/0.24 | 16.90/14.65 | S |
| iso/reused-wall | 20.655 | 20.622 | -0.159 | -7.27/+7.84/-5.20 | 0.97/0.22 | 16.87/14.60 | S |
| iso/source-cpu | 23.575 | 23.540 | -0.148 | -6.84/+7.36/-4.59 | 1.61/1.47 | 14.85/13.68 | S |
| iso/source-wall | 23.575 | 23.534 | -0.174 | -6.82/+7.38/-4.59 | 1.63/1.50 | 14.77/13.68 | S |
| rfc/reused-cpu | 17.760 | 17.665 | -0.535 | -6.99/+6.95/-4.71 | 1.55/0.59 | 16.27/13.59 | S |
| rfc/reused-wall | 17.754 | 17.654 | -0.560 | -7.01/+6.94/-4.71 | 1.56/0.59 | 16.32/13.64 | S |
| rfc/source-cpu | 20.450 | 20.295 | -0.758 | -7.67/+8.65/-4.93 | 2.18/0.44 | 17.36/14.54 | S |
| rfc/source-wall | 20.445 | 20.289 | -0.766 | -7.66/+8.61/-4.96 | 2.17/0.45 | 17.36/14.47 | S |
| unicode/reused-cpu | 22.040 | 22.205 | +0.749 | +0.20/+9.82/-5.99 | 0.45/1.28 | 13.11/13.92 | S |
| unicode/reused-wall | 22.035 | 22.198 | +0.738 | +0.22/+9.85/-5.96 | 0.44/1.27 | 13.05/13.97 | S |
| unicode/source-cpu | 24.785 | 24.770 | -0.061 | -2.04/+8.03/-4.44 | 1.19/0.40 | 10.29/15.54 | S |
| unicode/source-wall | 24.778 | 24.769 | -0.040 | -2.03/+8.04/-4.39 | 1.19/0.39 | 10.25/15.59 | S |
