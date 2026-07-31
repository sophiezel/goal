import React, { useEffect, useState } from "react";

export function SamplePage() {
  const [data, setData] = useState<unknown>(null);
  useEffect(() => {
    fetch("/api/sample").then((r) => r.json()).then(setData);
  }, []);
  return <div>{String(data)}</div>;
}
