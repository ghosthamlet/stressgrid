import * as React from 'react';
import * as ReactDOM from 'react-dom';

import { Provider } from 'mobx-react';

import './App.css';

import { library } from '@fortawesome/fontawesome-svg-core'
import { faCog, faFlag, faSpinner } from '@fortawesome/free-solid-svg-icons'

import App from './App';
import './index.css';
// import registerServiceWorker from './registerServiceWorker';

import generatorsStore from './stores/GeneratorsStore'
import reportsStore from './stores/ReportsStore';
import runsStore from './stores/RunsStore'
import ws from './Ws';

library.add(faSpinner)
library.add(faCog)
library.add(faFlag)

const wsUrl = location.port === "3000" ?
  'ws://localhost:8000/ws' :
  (location.protocol === "https:" ? "wss:" : "ws:") + "//" + location.host + "/ws";

ws.connect(wsUrl);

ReactDOM.render(
  <Provider generatorsStore={generatorsStore} runsStore={runsStore} reportsStore={reportsStore} ws={ws}>
    <App />
  </Provider>,
  document.getElementById('root') as HTMLElement
);
// registerServiceWorker();
