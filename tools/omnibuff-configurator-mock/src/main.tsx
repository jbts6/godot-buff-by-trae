import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import './index.css'
import App from './App.tsx'
import { ConfigProvider, theme } from 'antd'
import 'antd/dist/reset.css'

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <ConfigProvider
      theme={{
        algorithm: theme.darkAlgorithm,
        token: {
          colorPrimary: '#8cffea',
          colorInfo: '#8cffea',
          borderRadius: 12,
          colorBgBase: '#0b0d14',
          fontFamily: 'var(--sans)',
        },
      }}
    >
      <App />
    </ConfigProvider>
  </StrictMode>,
)
