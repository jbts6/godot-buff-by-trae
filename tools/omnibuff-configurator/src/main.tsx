import React from "react";
import ReactDOM from "react-dom/client";
import App from "./App";
import { ConfigProvider, theme } from "antd";
import "antd/dist/reset.css";
import "./styles/global.css";

ReactDOM.createRoot(document.getElementById("root") as HTMLElement).render(
  <React.StrictMode>
    <ConfigProvider
      theme={{
        algorithm: theme.darkAlgorithm,
        token: {
          colorPrimary: "#8cffea",
          colorInfo: "#8cffea",
          borderRadius: 12,
          colorBgBase: "#0b0d14",
        },
      }}
    >
      <App />
    </ConfigProvider>
  </React.StrictMode>,
);
