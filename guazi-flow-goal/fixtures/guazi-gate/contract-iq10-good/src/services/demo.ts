export function fetchDetail() {
  return createRequest({ key: 'CSP_GOOD', uri: '/external/demo/detail', source: 100 });
}
