import request from '@/utils/request';

const req = request.createRequest({ key: 'CSP_FACTORY', source: 100 });

export function fetchDetail() {
  return req({ uri: '/external/demo/detail' });
}
